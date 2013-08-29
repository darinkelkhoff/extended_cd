#################################################################################
##     File: extended_cd.bashrc
##      Des: Define a function to wrap the cd-builtin command, with extra features.
##   Author: Darin Kelkhoff
##    Notes:
##     Todo:
## Modified: Fri Aug 10 2007
##################################################################################



################################################
## define the max size of the CD_HISTORY file ##
################################################
CD_HISTORY_SIZE=250

########################################################
## define the location of the CD_HISTORY file (and a  ##
## location for a tmp copy of it while rebuilding it) ##
########################################################
CD_HISTORY=~/.cd_history
CD_HISTORY_NEW=~/.cd_history.new.$$.${HOSTNAME:-$(hostname)}


##########################################################################
## Function: cd
##     Desc: customzed cd command, that looks for specific patterns to help
##           navigate the file system faster.
##     Args: the first argument is checked for the patterns as described
##           in usage block below
##    Input:
##   Output:
##    Notes: Future ideas:
##########################################################################
function cd
{
   arg="$1";

   ######################################
   ## make sure CD_HISTORY file exists ##
   ######################################
   if [ ! -e $CD_HISTORY ]; then
      touch $CD_HISTORY
   fi

   ###############################
   ## check for a help argument ##
   ###############################
   if [ "$arg" = "-h" -o "$arg" = "-help" -o "$arg" = "--help" ]; then

      builtin cd -help 2>&1 | grep -v "invalid option"

      ############
      ## usage: ##
      ############
      echo
      echo "For extended features, use the following for [dir] (not compatible with [-L|-P] flags):"
      echo "   ?pattern   - Pick directory from cd_history matching <pattern>."
      echo "   .?pattern  - Pick directory from cd_history matching <pattern>, under cwd."
      echo "   _          - Go to last entry in cd_history."
      echo "   _number    - Go to <number>'th last entry in cd_history."
      echo "   ...pattern - Go up (multiple ../'s) to directory matching <pattern>."
      echo "   ^old^new   - Go to pwd, with pattern <old> replaced with <new>"
      echo "   _?         - List cd_history, prompt to select directory."
      echo "   _?number   - List last <number> cd_history entries, prompt to select directory."

      return;
   fi

   ####################################################
   ## sometimes one accidentally says "cd cd foo" -- ##
   ## if so, strip off the accidental cd argument    ##
   ####################################################
   if [ "$arg" = "cd" -a \! -z "$2" ]; then
      arg="$2";
   fi

   #################################################################
   ## check if invoked with an argument starting with a ? or a .? ##
   #################################################################
   if [ $(echo "$arg" | grep "^\.\??") ]; then

      ############################################
      ## if the argument started with dot, set  ##
      ## pwd.* as the start of the grep pattern ##
      ############################################
      patternPrefix=""
      if [ $(echo "$arg" | grep "^\.") ]; then
         patternPrefix="$(pwd).*"
      fi

      #################################################################
      ## look for a pattern after the ?, to filter the cd_history by ##
      #################################################################
      pattern=${patternPrefix}$(echo "$arg" | sed "s/^\.//" | sed "s/^?//");

      ##########################################################
      ## if pattern not given, default it to . (to match all) ##
      ##########################################################
      if [ -z "$pattern" ]; then
         pattern="."
      fi

      #####################################################################
      ## read the the cd history, sorted -u, and filtered by the pattern ##
      #####################################################################
      history=$(sort -u $CD_HISTORY | grep -e "$pattern")

      if [ -z "$history" ]; then
         echo "Sorry, no applicable cd history.";
         return;
      fi

      #################################
      ## prompt user for where to go ##
      #################################
      _cd_prompt "$history" "cat"

   ######################################################
   ## check for special argument "_" -- go to nth-last ##
   ## dir switched to, as recorded in history file     ##
   ######################################################
   elif [ $(echo "$arg" | grep "^_?\?[0-9]*$") ]; then

      ########################################################
      ## check for _? - to do prompting from end of history ##
      ########################################################
      doPrompt=""
      if [ $(echo "$arg" | grep "^_?") ]; then
         doPrompt="1"
      fi

      ############################
      ## check for number given ##
      ############################
      number=$(echo "$arg" | sed "s/^_//" | sed "s/^?//");
      if [ -z "$number" ]; then

         if [ -z "$doPrompt" ]; then

            ###########################################
            ## if not prompting, default number to 1 ##
            ###########################################
            number="1"

         else

            ################################################
            ## if prompting, default to full history size ##
            ################################################
            number="$CD_HISTORY_SIZE"

         fi
      fi

      ##################################################################
      ## if not doing prompt, just get line from history and go there ##
      ##################################################################
      if [ -z "$doPrompt" ]; then

         dir=$(tail -n $number $CD_HISTORY | head -1);
         builtin cd "$dir";

      else

         ##########################
         ## otherwise, do prompt ##
         ##########################
         ## _cd_prompt "$(tail -n ${number} $CD_HISTORY)" "tac"
         _cd_prompt "$(tail -n ${number} $CD_HISTORY)" "reverse"

      fi

      ############################################################################
      ## return here without letting this entry be re-added to the history file ##
      ############################################################################
      return;

   ######################################################
   ## check for special argument "...pattern" -- go up ##
   ## (ie, ..) until arrive in dir named by pattern.   ##
   ######################################################
   elif [ $(echo "$arg" | grep "^\.\.\..*$") ]; then

      pattern=$(echo "$arg" | sed "s/^\.\.\.//");

      target=$(pwd)

      while [ -z "$(echo $target | grep $pattern[^/]*$)" ]; do
         target=$(dirname $target)

         if [ -z "$target" ]; then
            echo "cd: ${pattern}: No such matching ancestor directory";
            return;
         fi
      done

      builtin cd $target;

   ####################################################################
   ## check for special argument "^old^new" - go to pwd after regexp ##
   ####################################################################
   elif [ $(echo "$arg" | grep "^\^.\+\^.\+") ]; then

      pattern=$(echo "$arg" | sed "s/\^$//")
      old=$(echo "$pattern" | sed "s/^\^//;s/\^.*//");
      new=$(echo "$pattern" | sed "s/^\^//;s/.*\^//");

      ##############################################
      ## couldn't this sed just use the orignial  ##
      ## arg as in: s${arg}^ ? Consider changing. ##
      ##############################################
      target=$(pwd | sed "s/$old/$new/")

      builtin cd $target;

   ##################################
   ## else default to normal usage ##
   ##################################
   else
      builtin cd "$@";
   fi

   ########################################################################
   ## remove the new cwd from .cd_history, then re-add it at the end (so ##
   ## it won't be duplicated, and it will be at the bottom of the file)  ##
   ########################################################################
   grep -v "^$(pwd)\$" $CD_HISTORY | tail -n $((CD_HISTORY_SIZE - 1)) \
       > $CD_HISTORY_NEW;
   pwd >> $CD_HISTORY_NEW;

   ######################################################################
   ## mv the updated file into place atomically so another shell won't ##
   ## ever see partial results.                                        ##
   ######################################################################
   mv $CD_HISTORY_NEW $CD_HISTORY
}



##########################################################################
## Function: _cd_prompt
##     Desc: display a list of options for a cd destination and prompt user
##     Args: history - list of dirs to display as options
##     Args: sort - useful as "cat" or "tac" - lets list be sorted
##                  & numbered forward or backward (tac -> backward)
##    Input:
##   Output:
##    Notes:
##########################################################################
function _cd_prompt
{
   history="$1"
   sort="$2"

   ############
   ## prompt ##
   ############
   echo "$history" | $sort | cat -n | $sort | awk '{ print $0, $1; }' | sed "s/\( \+\w\+\)\(.\+\) \(\w\+$\)/${YELLOW}\1${RESET} \2 ${YELLOW}\3${RESET}/"
   echo -n "${YELLOW}cd${RESET}> ";
   read answer;

   ########################################
   ## if no answer given, take no action ##
   ########################################
   if [ -z "$answer" ]; then
      return;
   fi

   ####################################
   ## check if answer is all numbers ##
   ####################################
   nonums="$(echo $answer | sed 's/[0-9]//g')"
   if [ ! -z "$nonums" ] ; then

      #######################################################################
      ## if line isn't all numbers, take it to mean the directory to cd to ##
      #######################################################################
      dir="$answer";

   else

      ################################################################################
      ## if line is all numbers, use it to mean a line from the list of files above ##
      ################################################################################
      dir="$(echo "$history" | $sort | head -${answer} | tail -n 1)"

   fi

   builtin cd "$dir";
}



##########################################################################
## Function: cd-clean
##     Desc: clean no longer existing entries from the CD_HISTORY file
##     Args:
##    Input:
##   Output: A note about how many lines were kept
##    Notes:
##########################################################################
function cd-clean
{
   for i in $(cat $CD_HISTORY); do
      if [ -d $i ]; then
         echo $i >> $CD_HISTORY_NEW;
      fi
   done

   mv $CD_HISTORY_NEW $CD_HISTORY

   lines=$(cat $CD_HISTORY | wc -l)
   echo "Keeping $lines lines of cd_history."
}



##########################################################################
## Function: reverse
##     Desc: for systems without a 'tac' command, use this to 'tac' a file.
##     Args:
##    Input:
##   Output:
##    Notes:
##########################################################################
function reverse
{
   local line
   if IFS= read -r line
   then
      reverse
      printf '%s\n' "$line"
   fi
}
