BEGIN {
  Shell = "bash" # default shell
  SupportedShells["bash"]
  SupportedShells["sh"]
  SupportedOptions["tracing"]
  SupportedOptions["silent"]
  SupportedOptions["timing"]
  Tmp = isDir("/dev/shm") ? "/dev/shm" : "/tmp"
  split("",Lines)
  split("",Args) # parsed CLI args
  split("",ArgGoals) # invoked goals
  split("",Options)
  split("",GoalNames)   # list
  split("",GoalsByName) # name -> private
  split("",Code)        # name -> body
  split("",DefineOverrides) # k -> ""
  DefinesFile=""
  split("",Dependencies)       # name,i -> dep goal
  split("",DependenciesLineNo) # name,i -> line no.
  split("",DependenciesCnt)    # name   -> dep cnd
  split("",Doc)       # name -> doc str
  split("",ReachedIf) # name -> condition line
  GlobCnt = 0         # count of files for glob
  GlobGoalName = ""
  split("",GlobFiles) # list
  split("",LibNames) # list
  split("",Lib)      # name -> code
  split("",UseLibLineNo)# name -> line no.
  split("",GoalToLib)# goal name -> lib name
  Mode = "prelude" # prelude|goal|goal_glob|lib
  srand()
  prepareArgs()
  MyDirScript = "MYDIR=" quoteArg(getMyDir(ARGV[1])) ";export MYDIR;cd \"$MYDIR\""
  Error=""
}

{
  Lines[NR]=$0
  if ($1 ~ /^@/ && "@define" != $1) reparseCli()
  if ("@options" == $1) handleOptions()
  else if ("@define" == $1) handleDefine()
  else if ("@shell" == $1) handleShell()
  else if ("@goal" == $1) { if ("@glob" == $2 || "@glob" == $3) handleGoalGlob(); else handleGoal() }
  else if ("@doc" == $1) handleDoc()
  else if ("@depends_on" == $1) handleDependsOn()
  else if ("@reached_if" == $1) handleReachedIf()
  else if ("@lib" == $1) handleLib()
  else if ("@use_lib" == $1) handleUseLib()
  else if ($1 ~ /^@/) addError("Unknown directive: " $1)
  else handleCodeLine($0)
}


END { if (!Died) doWork() }

function prepareArgs(   i,arg) {
  for (i = 2; i < ARGC; i++) {
    arg = ARGV[i]
    #print i " " arg
    if (substr(arg,1,1) == "-") {
      if (arg == "-f" || arg == "--file") {
        delete ARGV[i]
        ARGV[1] = ARGV[++i]
      } else if (arg == "-D" || arg == "--define") {
        delete ARGV[i]
        handleOptionDefineOverride(ARGV[++i])
      } else
        Args[arg]
    } else
      arrPush(ArgGoals, arg)

    delete ARGV[i] # https://unix.stackexchange.com/a/460375
  }
  if ("-h" in Args || "--help" in Args) {
    print "makesure ver. " Version
    print "Usage: makesure [options...] [-f buildfile] [goals...]"
    print " -f,--file buildfile"
    print "                 set buildfile to use (default Makesurefile)"
    print " -l,--list       list all available non-@private goals"
    print " -la,--list-all  list all available goals"
    print " -d,--resolved   list resolved dependencies to reach given goals"
    print " -D \"var=val\",--define \"var=val\""
    print "                 override @define values"
    print " -s,--silent     silent mode - only output what goals output"
    print " -t,--timing     display execution times for goals and total"
    print " -x,--tracing    enable tracing in bash/sh via `set -x`"
    print " -v,--version    print version and exit"
    print " -h,--help       print help and exit"
    print " -U,--selfupdate update makesure to latest version"
    realExit(0)
  } else if ("-v" in Args || "--version" in Args) {
    print Version
    realExit(0)
  } else if ("-U" in Args || "--selfupdate" in Args) {
    selfUpdate()
    realExit(0)
  }
  if (!isFile(ARGV[1])) {
    if (isFile(ARGV[1] "/Makesurefile"))
      ARGV[1] = ARGV[1] "/Makesurefile"
    else
      die("makesure file not found: " ARGV[1])
  }
  if ("-s" in Args || "--silent" in Args)
    Options["silent"]
  if ("-x" in Args || "--tracing" in Args)
    Options["tracing"]
  if ("-t" in Args || "--timing" in Args)
    Options["timing"]
}

#function dbgA(name, arr,   i) { print "--- " name ": "; for (i in arr) printf "%2s : %s\n", i, arr[i] }
#function dbgAO(name, arr,   i) { print "--- " name ": "; for (i=0;i in arr;i++) printf "%2s : %s\n", i, arr[i] }

function splitKV(arg, kv,   n) {
  n = index(arg, "=")
  kv[0] = trim(substr(arg,1,n-1))
  kv[1] = trim(substr(arg,n+1))
}
function handleOptionDefineOverride(arg,   kv) {
  splitKV(arg, kv)
  handleDefineLine(kv[0] "=" quoteArg(kv[1]))
  DefineOverrides[kv[0]]
}

function handleOptions(   i) {
  checkPreludeOnly()

  if (NF<2)
    addError("Provide at least one option")

  for (i=2; i<=NF; i++) {
    if (!($i in SupportedOptions))
      addError("Option '" $i "' is not supported")
    Options[$i]
  }
}

function handleDefine() {
  checkPreludeOnly()
  $1 = ""
  handleDefineLine($0)
}
function handleDefineLine(line,   kv,l) {
  if (!DefinesFile)
    DefinesFile = executeGetLine("mktemp " Tmp "/makesure.XXXXXXXXXX")

  splitKV(line, kv)

  if (!(kv[0] in DefineOverrides)) {
    handleCodeLine(l = line "; export " kv[0])
    handleCodeLine("echo " quoteArg(l) " >> " DefinesFile)
  }
}

function handleShell() {
  checkPreludeOnly()

  Shell = trim($2)

  if (!(Shell in SupportedShells))
    addError("Shell '" Shell "' is not supported")
}

function adjustOptions() {
  if ("silent" in Options)
    delete Options["timing"]
}

function started(mode) {
  if (isPrelude()) adjustOptions()
  Mode = mode
}

function handleLib(   libName) {
  started("lib")

  libName = trim($2)
  if (libName in Lib) {
    addError("Lib '" libName "' is already defined")
  }
  arrPush(LibNames, libName)
  Lib[libName]
}

function handleUseLib(   i) {
  checkGoalOnly()

  if ("goal" == Mode)
    registerUseLib(currentGoalName())
  else {
    for (i=0; i < GlobCnt; i++){
      registerUseLib(globGoal(i))
    }
  }
}

function registerUseLib(goalName) {
  if (goalName in GoalToLib)
    addError("You can only use one @lib in a @goal")

  GoalToLib[goalName] = $2
  UseLibLineNo[goalName] = NR
}

function handleGoal(   priv) {
  started("goal")
  priv = parseGoalLine()
  registerGoal($0, priv)
}

function registerGoal(goalName, priv) {
  goalName = trim(goalName)
  if (length(goalName) == 0)
    addError("Goal must have a name")
  if (goalName in GoalsByName)
    addError("Goal " quote2(goalName,1) " is already defined")
  arrPush(GoalNames, goalName)
  GoalsByName[goalName] = priv
}

function globGoal(i) { return (GlobGoalName ? GlobGoalName "@" : "") GlobFiles[i] }
function calcGlob(goalName, pattern,   script, file) {
  GlobCnt = 0
  GlobGoalName = goalName
  split("",GlobFiles)
  gsub(/ /,"\\ ",pattern)
  script = MyDirScript ";for f in ./" pattern ";do test -e \"$f\" && echo \"$f\";done"
  while ((script | getline file)>0) {
    GlobCnt++
    file = substr(file, 3)
    arrPush(GlobFiles,file)
  }
  close(script)
  quicksort(GlobFiles,0,arrLen(GlobFiles)-1)
}

function parseGoalLine(   priv) {
  if ($NF == "@private") {
    priv=1
    NF--
  }
  $1 = ""
  return priv
}

function handleGoalGlob(   goalName,globAllGoal,globSingle,priv,i,pattern) {
  started("goal_glob")
  priv = parseGoalLine()
  goalName = $2; $2 = ""
  if ("@glob" == goalName) {
    goalName = ""
  } else $3 = ""
  calcGlob(goalName, pattern = trim($0))
  globAllGoal = goalName ? goalName : pattern
  globSingle = GlobCnt == 1 && globAllGoal == globGoal(0)
  for (i=0; i < GlobCnt; i++){
    registerGoal(globGoal(i), globSingle ? priv : 1)
  }
  if (!globSingle) { # glob on single file
    registerGoal(globAllGoal, priv)
    for (i=0; i < GlobCnt; i++){
      registerDependency(globAllGoal, globGoal(i))
    }
  }
}

function handleDoc(   i) {
  checkGoalOnly()

  if ("goal" == Mode) {
    registerDoc(currentGoalName())
  } else {
    if (!(GlobCnt == 1 && currentGoalName() == globGoal(0))) # glob on single file
      registerDoc(currentGoalName())
    for (i=0; i < GlobCnt; i++){
      registerDoc(globGoal(i))
    }
  }
}

function registerDoc(goalName) {
  if (goalName in Doc)
    addError("Multiple " $1 " not allowed for a goal")
  $1 = ""
  Doc[goalName] = trim($0)
}

function handleDependsOn(   i) {
  checkGoalOnly()

  if (NF<2)
    addError("Provide at least one dependency")

  if ("goal" == Mode)
    registerDependsOn(currentGoalName())
  else {
    for (i=0; i < GlobCnt; i++){
      registerDependsOn(globGoal(i))
    }
  }
}

function registerDependsOn(goalName,   i) {
  for (i=2; i<=NF; i++)
    registerDependency(goalName, $i)
}

function registerDependency(goalName, depGoalName,   x) {
  Dependencies[x = goalName SUBSEP DependenciesCnt[goalName]++] = depGoalName
  DependenciesLineNo[x] = NR
}

function handleReachedIf(   i) {
  checkGoalOnly()

  if ("goal" == Mode)
    registerReachedIf(currentGoalName())
  else {
    for (i=0; i < GlobCnt; i++){
      registerReachedIf(globGoal(i), makeGlobVarsCode(i))
    }
  }
}

function makeGlobVarsCode(i) {
  return "ITEM=" quoteArg(GlobFiles[i]) ";INDEX=" i ";TOTAL=" GlobCnt ";"
}

function registerReachedIf(goalName, preScript) {
  if (goalName in ReachedIf)
    addError("Multiple " $1 " not allowed for a goal")

  $1 = ""
  ReachedIf[goalName] = preScript trim($0)
}

function checkBeforeRun(   i,dep,depCnt,goalName) {
  for (goalName in GoalsByName) {
    depCnt = DependenciesCnt[goalName]
    for (i=0; i < depCnt; i++) {
      dep = Dependencies[goalName, i]
      if (!(dep in GoalsByName))
        addError("Goal " quote2(goalName,1) " has unknown dependency '" dep "'", DependenciesLineNo[goalName, i])
    }
    if (goalName in GoalToLib) {
      if (!(GoalToLib[goalName] in Lib))
        addError("Goal " quote2(goalName,1) " uses unknown lib '" GoalToLib[goalName] "'", UseLibLineNo[goalName])
    }
  }
}

function doWork(\
  i,j,goalName,gnLen,gnMaxLen,depCnt,dep,reachedIf,reachedGoals,emptyGoals,definesLine,
body,goalBody,goalBodies,resolvedGoals,exitCode, t0,t1,t2, goalTimed, list) {

  started("end") # end last directive

  checkBeforeRun()

  if (Error)
    die(Error)

  list="-l" in Args || "--list" in Args
  if (list || "-la" in Args || "--list-all" in Args) {
    print "Available goals:"
    for (i = 0; i in GoalNames; i++) {
      goalName = GoalNames[i]
      if (list && GoalsByName[goalName]) # private
        continue
      if ((gnLen = length(quote2(goalName))) > gnMaxLen && gnLen <= 30)
        gnMaxLen = gnLen
    }
    for (i = 0; i in GoalNames; i++) {
      goalName = GoalNames[i]
      if (list && GoalsByName[goalName]) # private
        continue
      printf "  "
      if (goalName in Doc)
        printf "%-" gnMaxLen "s : %s\n", quote2(goalName), Doc[goalName]
      else
        print quote2(goalName)
    }
  } else {
    if ("timing" in Options)
      t0 = currentTimeMillis()

    if (length(body = trim(Code[""])) > 0) {
      # run prelude first to process all @defines
      goalBody[0] = MyDirScript
      if ("tracing" in Options)
        addLine(goalBody, "set -x")
      addLine(goalBody, body)
      exitCode = shellExec(goalBody[0])
      if (exitCode != 0) {
        print "  prelude failed"
        realExit(exitCode)
      }
    }

    addLine(definesLine, MyDirScript)
    if (DefinesFile)
      addLine(definesLine, ". " DefinesFile)

    for (i = 0; i in GoalNames; i++) {
      goalName = GoalNames[i]

      body = trim(Code[goalName])

      reachedIf = ReachedIf[goalName]
      reachedGoals[goalName] = reachedIf ? checkConditionReached(definesLine[0], reachedIf) : 0
      emptyGoals[goalName] = length(body) == 0

      depCnt = DependenciesCnt[goalName]
      for (j=0; j < depCnt; j++) {
        dep = Dependencies[goalName, j]
        if (!reachedGoals[goalName]) {
          # we only add a dependency to this goal if it's not reached
          #print " [not reached] " goalName " -> " dep
          topologicalSortAddConnection(goalName, dep)
        } else {
          #print " [    reached] " goalName " -> " dep
        }
      }

      goalBody[0] = ""
      addLine(goalBody, definesLine[0])
      if (goalName in GoalToLib)
        addLine(goalBody, Lib[GoalToLib[goalName]])

      if ("tracing" in Options)
        addLine(goalBody, "set -x")

      addLine(goalBody, body)
      goalBodies[goalName] = goalBody[0]
    }

    resolveGoalsToRun(resolvedGoals)

    if ("-d" in Args || "--resolved" in Args) {
      printf "Resolved goals to reach for"
      for (i = 0; i in ArgGoals; i++)
        printf " %s", quote2(ArgGoals[i],1)
      print ":"
      for (i = 0; i in resolvedGoals; i++)
        print "  " quote2(resolvedGoals[i])
    } else {
      for (i = 0; i in resolvedGoals; i++) {
        goalName = resolvedGoals[i]
        goalTimed = "timing" in Options && !reachedGoals[goalName] && !emptyGoals[goalName]
        if (goalTimed)
          t1 = t2 ? t2 : currentTimeMillis()

        if (!("silent" in Options))
          print "  goal " quote2(goalName,1) " " (reachedGoals[goalName] ? "[already satisfied]." : emptyGoals[goalName] ? "[empty]." : "...")

        exitCode = (reachedGoals[goalName] || emptyGoals[goalName]) ? 0 : shellExec(goalBodies[goalName])
        if (exitCode != 0)
          print "  goal " quote2(goalName,1) " failed"
        if (goalTimed) {
          t2 = currentTimeMillis()
          print "  goal " quote2(goalName,1) " took " renderDuration(t2 - t1)
        }
        if (exitCode != 0)
          break
      }
      if ("timing" in Options)
        print "  total time " renderDuration((t2 ? t2 : currentTimeMillis()) - t0)
      if (exitCode != 0)
        realExit(exitCode)
    }

    realExit(0)
  }
}

function resolveGoalsToRun(result,   i, goalName, loop) {
  if (arrLen(ArgGoals) == 0)
    arrPush(ArgGoals, "default")

  for (i = 0; i in ArgGoals; i++) {
    goalName = ArgGoals[i]
    if (!(goalName in GoalsByName)) {
      die("Goal not found: " goalName)
    }
    topologicalSortPerform(goalName, result, loop)
  }

  if (loop[0] == 1) {
    die("There is a loop in goal dependencies via " loop[1] " -> " loop[2])
  }
}

function isPrelude() { return "prelude"==Mode }
function checkPreludeOnly() { if (!isPrelude()) addError("Only use " $1 " in prelude") }
function checkGoalOnly() { if ("goal" != Mode && "goal_glob" != Mode) addError("Only use " $1 " in @goal") }
function currentGoalName() { return isPrelude() ? "" : arrLast(GoalNames) }
function currentLibName() { return arrLast(LibNames) }

function realExit(code) {
  Died = 1
  if (DefinesFile)
    rm(DefinesFile)
  exit code
}
function addError(err, n) { if (!n) n=NR; Error=addL(Error, err ":\n" ARGV[1] ":" n ": " Lines[n]) }
function die(msg,    out) {
  out = "cat 1>&2" # trick to write from awk to stderr
  print msg | out
  close(out)
  realExit(1)
}

function checkConditionReached(definesLine, conditionStr,    script) {
  script = definesLine # need this to initialize variables for check conditions
  script = script "\n" conditionStr
  #print "script: " script
  return shellExec(script) == 0
}

function shellExec(script,   res) {
  script = Shell " -e -c " quoteArg(script)

  #print script
  res = system(script)
  #print "res " res
  return res
}

function getMyDir(makesurefilePath) {
  return executeGetLine("cd \"$(dirname " quoteArg(makesurefilePath) ")\";pwd")
}

function handleCodeLine(line,   goalName, name, i) {
  if ("lib" == Mode) {
    name = currentLibName()
    #print "Append line for '" name "': " line
    Lib[name] = addL(Lib[name], line)
  } else if ("goal_glob" == Mode) {
    for (i=0; i < GlobCnt; i++){
      if (!Code[goalName = globGoal(i)])
        addCodeLine(goalName, makeGlobVarsCode(i))
      addCodeLine(goalName, line)
    }
  } else
    addCodeLine(currentGoalName(), line)
}

function addCodeLine(name, line) {
  #print "Append line for '" name "': " line
  Code[name] = addL(Code[name], line)
}

function topologicalSortAddConnection(from, to) {
  # Slist - list of successors by node
  # Scnt - count of successors by node
  Slist[from, ++Scnt[from]] = to # add 'to' to successors of 'from'
}

function topologicalSortPerform(node, result, loop,   i, s) {
  if (Visited[node] == 2)
    return

  Visited[node] = 1

  for (i = 1; i <= Scnt[node]; i++) {
    if (Visited[s = Slist[node, i]] == 0)
      topologicalSortPerform(s, result, loop)
    else if (Visited[s] == 1) {
      loop[0] = 1
      loop[1] = s
      loop[2] = node
    }
  }

  Visited[node] = 2

  arrPush(result, node)
}

function currentTimeMillis(   res) {
  if (Gawk)
    return int(gettimeofday()*1000)
  res = executeGetLine("date +%s%3N")
  sub(/%?3N/, "000", res) # if date doesn't support %N (macos?) just use second-precision
  return +res
}

function selfUpdate(   url, tmp, err, newVer) {
  url = "https://raw.githubusercontent.com/xonixx/makesure/main/makesure?token=" rand()
  tmp = executeGetLine("mktemp /tmp/makesure_new.XXXXXXXXXX")
  err = dl(url, tmp)
  if (!err && !ok("chmod +x " tmp)) err = "can't chmod +x " tmp
  if (!err) {
    newVer = executeGetLine(tmp " -v")
    if (Version != newVer) {
      if (!ok("cp " tmp " " quoteArg(Prog)))
        err = "can't overwrite " Prog
      else print "updated " Version " -> " newVer
    } else print "you have latest version " Version " installed"
  }
  rm(tmp)
  if (err) die(err)
}

function renderDuration(deltaMillis,\
  deltaSec,deltaMin,deltaHr,deltaDay,dayS,hrS,minS,secS,secSI,res) {

  deltaSec = deltaMillis / 1000
  deltaMin = 0
  deltaHr = 0
  deltaDay = 0

  if (deltaSec >= 60) {
    deltaMin = int(deltaSec / 60)
    deltaSec = deltaSec - deltaMin * 60
  }

  if (deltaMin >= 60) {
    deltaHr = int(deltaMin / 60)
    deltaMin = deltaMin - deltaHr * 60
  }

  if (deltaHr >= 24) {
    deltaDay = int(deltaHr / 24)
    deltaHr = deltaHr - deltaDay * 24
  }

  dayS = deltaDay > 0 ? deltaDay " d" : ""
  hrS = deltaHr > 0 ? deltaHr " h" : ""
  minS = deltaMin > 0 ? deltaMin " m" : ""
  secS = deltaSec > 0 ? deltaSec " s" : ""
  secSI = deltaSec > 0 ? int(deltaSec) " s" : ""

  if (dayS != "")
    res = dayS " " (hrS == "" ? "0 h" : hrS)
  else if (deltaHr > 0)
    res = hrS " " (minS == "" ? "0 m" : minS)
  else if (deltaMin > 0)
    res = minS " " (secSI == "" ? "0 s" : secSI)
  else
    res = deltaSec > 0 ? secS : "0 s"

  return res
}
function executeGetLine(script,   res) {
  script | getline res
  close(script)
  return res
}
function dl(url, dest,    verbose) {
  verbose = "VERBOSE" in ENVIRON
  if (commandExists("wget")) {
    if (!ok("wget " (verbose ? "" : "-q") " " quoteArg(url) " -O" quoteArg(dest)))
      return "error with wget"
  } else if (commandExists("curl")) {
    if (!ok("curl " (verbose ? "" : "-s") " " quoteArg(url) " -o " quoteArg(dest)))
      return "error with curl"
  } else return "wget/curl no found"
}
# s1 > s2 -> 1
# s1== s2 -> 0
# s1 < s2 -> -1
function natOrder(s1,s2, i1,i2,   c1, c2, n1,n2) {
  if (_digit(c1 = substr(s1,i1,1)) && _digit(c2 = substr(s2,i2,1))) {
    n1 = +c1; while(_digit(c1 = substr(s1,++i1,1))) { n1 = n1 * 10 + c1 }
    n2 = +c2; while(_digit(c2 = substr(s2,++i2,1))) { n2 = n2 * 10 + c2 }

    return n1 == n2 ? natOrder(s1, s2, i1, i2) : _cmp(n1, n2)
  }

  # consume till equal substrings
  while ((c1 = substr(s1,i1,1)) == (c2 = substr(s2,i2,1)) && c1 != "" && !_digit(c1)) {
    i1++; i2++
  }

  return _digit(c1) && _digit(c2) ? natOrder(s1, s2, i1, i2) : _cmp(c1, c2)
}
function _cmp(v1, v2) { return v1 > v2 ? 1 : v1 < v2 ? -1 : 0 }
function _digit(c) { return c >= "0" && c <= "9" }
function quicksort(data, left, right,   i, last) {
  if (left >= right)
    return
  quicksortSwap(data, left, int((left + right) / 2))
  last = left
  for (i = left + 1; i <= right; i++)
    if (natOrder(data[i], data[left],1,1) < 0)
      quicksortSwap(data, ++last, i)
  quicksortSwap(data, left, last)
  quicksort(data, left, last - 1)
  quicksort(data, last + 1, right)
}
function quicksortSwap(data, i, j,   temp) {
  temp = data[i]
  data[i] = data[j]
  data[j] = temp
}
function parseCli(line, res,   pos,c,last,is_doll,c1) {
  for(pos=1;;) {
    while((c = substr(line,pos,1))==" " || c == "\t") pos++ # consume spaces
    if ((c = substr(line,pos,1))=="#" || c=="")
      return
    else {
      if ((is_doll = c == "$") && substr(line,pos+1,1)=="'" || c == "'") { # start of string
        if(is_doll)
          pos++
          # consume quoted string
        res[last = res[-7]++] = ""
        while((c = substr(line,++pos,1)) != "'") { # closing '
          if (c=="")
            return "unterminated argument"
          else if (is_doll && c=="\\" && ((c1=substr(line,pos+1,1))=="'" || c1==c)) { # escaped ' or \
            c = c1; pos++
          }
          res[last] = res[last] c
        }
        if((c = substr(line,++pos,1)) != "" && c != " " && c != "\t")
          return "joined arguments"
      } else {
        # consume unquoted argument
        res[last = res[-7]++] = c
        while((c = substr(line,++pos,1)) != "" && c != " " && c != "\t") { # whitespace denotes end of arg
          if(c=="'")
            return "joined arguments"
          res[last] = res[last] c
        }
      }
    }
  }
}
function reparseCli(   res,i,err) {
  err = parseCli($0, res)
  if (err) {
    addError("Syntax error: " err)
    die(Error)
  } else
    for (i=NF=0; i in res; i++)
      $(++NF)=res[i]
}
function quote2(s,force) {
  if (index(s,"'")) {
    gsub(/\\/,"\\\\",s)
    gsub(/'/,"\\'",s)
    return "$'" s "'"
  } else
    return force || s ~ /[^a-zA-Z0-9.,@_\/=+-]/ ? "'" s "'" : s
}
function addLine(target, line) { target[0] = addL(target[0], line) }
function addL(s, l) { return s ? s "\n" l : l }
function arrPush(arr, elt) { arr[arr[-7]++] = elt }
function arrLen(arr) { return +arr[-7] }
function arrLast(arr) { return arr[arrLen(arr)-1] }
function commandExists(cmd) { return ok("command -v " cmd " >/dev/null") }
function ok(cmd) { return system(cmd) == 0 }
function isFile(path) { return ok("test -f " quoteArg(path)) }
function isDir(path) { return ok("test -d " quoteArg(path)) }
function rm(f) { system("rm " quoteArg(f)) }
function quoteArg(a) { gsub("'", "'\\''", a); return "'" a "'" }
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function gettimeofday(){} # hack for mawk