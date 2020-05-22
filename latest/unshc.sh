#!/bin/bash
###################
# Author: Luiz Otavio Duarte a.k.a. (LOD)
#  11/03/08 - v0.1
# Updated: Yann CAM v0.2 - yann.cam@gmail.com | www.asafety.fr
#  06/27/13 - v0.2
#  -- Adding new objdump format (2.22) to retrieve data (especially on Ubuntu distribution)
#  -- Patch few regex with sorted address list
# Updated: Yann CAM v0.3 - yann.cam@gmail.com | www.asafety.fr
#  18/11/15 - v0.3
#  -- Adapt script for new architecture
#  -- Clean and optimize functions
#  -- Add an (unsigned long) cast in shc C source code
# Updated: Yann CAM v0.4 - yann.cam@gmail.com | www.asafety.fr
#  14/12/15 - v0.4
#  -- Comment specific return statement in C source
# Updated: Yann CAM v0.5 - yann.cam@gmail.com | www.asafety.fr
#  15/12/15 - v0.5
#  -- Patch extract arc4 function to keep the latest offset only
# Updated: Yann CAM v0.6 - yann.cam@gmail.com | www.asafety.fr
#  16/12/15 - v0.6
#  -- Add bash script options (getopts)
# Updated: Yann CAM v0.7 - yann.cam@gmail.com | www.asafety.fr
#  07/28/16 - v0.7
#  -- Add support of multiple ARC4 offsets auto-retrieved by script (iterate over each one), specialy for huge bash file encrypted
#  -- Force .sh extension to decrypted file, for initial file without extension (prevent rewrite of original file)
# Updated: Yann CAM v0.8 - yann.cam@gmail.com | www.asafety.fr
#  01/23/17 - v0.8
#  -- Adjust grep for retrieve PWD_SIZE in OBJDUMP to ignore movb instruction (https://github.com/yanncam/UnSHc/issues/12)
###################
# Tested on :
#  Ubuntu 14.04.3 LTS x86_64
#    Linux server 3.13.0-61-generic #100-Ubuntu SMP Wed Jul 29 11:21:34 UTC 2015 x86_64 x86_64 x86_64 GNU/Linux
#    Linux version 3.13.0-61-generic (buildd@lgw01-50) (gcc version 4.8.2 (Ubuntu 4.8.2-19ubuntu1) ) #100-Ubuntu SMP Wed Jul 29 11:21:34 UTC 2015
#
#  CentOS release 6.6 (Final) x86_64
#    Linux server 2.6.32-504.23.4.el6.x86_64 #1 SMP Tue Jun 9 20:57:37 UTC 2015 x86_64 x86_64 x86_64 GNU/Linux
#    Linux version 2.6.32-504.23.4.el6.x86_64 (mockbuild@c6b9.bsys.dev.centos.org) (gcc version 4.4.7 20120313 (Red Hat 4.4.7-11) (GCC) ) #1 SMP Tue Jun 9 20:57:37 UTC 2015
#
#  Debian 7.8 i686
#    Linux server 3.2.0-4-686-pae #1 SMP Debian 3.2.68-1+deb7u2 i686 GNU/Linux
#    Linux version 3.2.0-4-686-pae (debian-kernel@lists.debian.org) (gcc version 4.6.3 (Debian 4.6.3-14) ) #1 SMP Debian 3.2.68-1+deb7u2
###################
VERSION="0.8"

OBJDUMP=$(which objdump)
GREP=$(which grep)
CUT=$(which cut)
SHRED=$(which shred)
UNIQ=$(which uniq)
SORT=$(which sort)
GCC=$(which gcc)
WC=$(which wc)
AWK=$(which awk)
SED=$(which sed)
TR=$(which tr)
HEAD=$(which head)
TAIL=$(which tail)

BINARY=""
TMPBINARY=$(mktemp /tmp/XXXXXX)
DUMPFILE=""
STRINGFILE=""
CALLFILE=$(mktemp /tmp/XXXXXX)
CALLADDRFILE=$(mktemp /tmp/XXXXXX)
CALLSIZEFILE=$(mktemp /tmp/XXXXXX)

declare -A LISTOFCALL

# Variable to know the index of variables.
# This var is to loop on each 14 arc4() call with ordered args.
j=0

# Simple usage help / man
function usage(){
        printf "[*] Usage : $0 [OPTIONS] <file.sh.x>\n"
        printf "\t -h | --help                          : print this help message\n"
        printf "\t -a OFFSET | --arc4 OFFSET            : specify the arc4() offset arbitrarily (without 0x prefix)\n"
        printf "\t -d DUMPFILE | --dumpfile DUMPFILE    : provide an object dump file (objdump -D script.sh.x > DUMPFILE)\n"
        printf "\t -s STRFILE | --stringfile STRFILE    : provide a string dump file (objdump -s script.sh.x > STRFILE)\n"
        printf "\t -o OUTFILE | --outputfile OUTFILE    : indicate the output file name\n\n"
        printf "[*] e.g : \n"
        printf "\t$0 script.sh.x\n"
        printf "\t$0 script.sh.x -o script_decrypted.sh\n"
        printf "\t$0 script.sh.x -a 400f9b\n"
        printf "\t$0 script.sh.x -d /tmp/dumpfile -s /tmp/strfile\n"
        printf "\t$0 script.sh.x -a 400f9b -d /tmp/dumpfile -s /tmp/strfile -o script_decrypted.sh\n"
}

# Clean all temp file created for this script
function clean(){
        $SHRED -zu -n 1 "$DUMPFILE" "$CALLFILE" "$CALLADDRFILE" "$CALLSIZEFILE" "$STRINGFILE" "$TMPBINARY" "${TMPBINARY}".c >/dev/null 2>&1
}

# Clean error exit function after cleaning temp file
function exit_error(){
        clean
        exit 1;
}

# Check the availability of basic commands usefull for this script
function check_binaries() {
        if [ ! -x "${OBJDUMP}" ]; then
                echo "[-] Error, cannot execute or find objdump binary"
                exit_error
        fi
        if [ ! -x "${GREP}" ]; then
                echo "[-] Error, cannot execute or find grep binary"
                exit_error
        fi
        if [ ! -x "${CUT}" ]; then
                echo "[-] Error, cannot execute or find cut binary"
                exit_error
        fi
        if [ ! -x "${SHRED}" ]; then
                echo "[-] Error, cannot execute or find shred binary"
                exit_error
        fi
        if [ ! -x "${UNIQ}" ]; then
                echo "[-] Error, cannot execute or find uniq binary"
                exit_error
        fi
        if [ ! -x "${SORT}" ]; then
                echo "[-] Error, cannot execute or find sort binary"
                exit_error
        fi
        if [ ! -x "${GCC}" ]; then
                echo "[-] Error, cannot execute or find gcc binary"
                exit_error
        fi
        if [ ! -x "${WC}" ]; then
                echo "[-] Error, cannot execute or find wc binary"
                exit_error
        fi
}

# Create dump files of encrypted script
function generate_dump() {
        # DUMPFILE dump to retrive arc4 address, address and size of each arc4 arguments and pwd
        $OBJDUMP -D "$BINARY" > "$DUMPFILE"
        # STRINGFILE dump to retrieve pwd and arc4 argument
        $OBJDUMP -s "$BINARY" > "$STRINGFILE"
}

# Find out the most called function. This function is arc4() and there are 14 calls.
# Update 27/06/2013 : Regexps updated to match new objdump format and retrieve the $CALLADDR from his number of call (bug initial with "sort")
# Update 16/11/2015 : Adding new architecture support
# Update 28/07/2016 : Adding multiple ARC4 offsets support (loop on each candidate)
function extract_arc4_call_addr(){
	TAILNUMBER=$1
	CALLADDRS=$($GREP -Eo "call.*[0-9a-f]{6,}" "$DUMPFILE" | $GREP -Eo "[0-9a-f]{6,}" | $SORT | $UNIQ -c | $SORT | $GREP -Eo "(14).*[0-9a-f]{6,}" | $GREP -Eo "[0-9a-f]{6,}")
	TAILMAX=$(wc -l <<< "$CALLADDRS")
        CALLADDR=$(echo "$CALLADDRS" | $SED "s/ /\n/g" | $TAIL -n "$TAILNUMBER" | $HEAD -n 1)
        if [[ -z "$CALLADDR" || $TAILNUMBER -gt $TAILMAX ]]; then
           echo "[-] Unable to define arc4() call address..."
           exit_error
        fi
        echo "[+] ARC4 address call candidate : [0x$CALLADDR]"
}

# Extract each args values of arc4 calls
function extract_variables_from_binary(){
        echo "[*] Extracting each args address and size for the 14 arc4() calls with address [0x$CALLADDR]..."
        # Initialize the number of line before CALLADDR to looking for addresses of args
        i=2
        # Retrieve ordered list of address var and put it to $CALLADDRFILE
        while [[ $($WC -l < "$CALLADDRFILE") -ne 14 ]]; do
                $GREP -B $i "call.*$CALLADDR" "$DUMPFILE" | $GREP -v "$CALLADDR" | $GREP -Eo "(0x[0-9a-f]{6,})" > "$CALLADDRFILE"
                i=$(($i + 1))
                if [ $i -eq 10 ]; then
                        echo "[-] Unable to extract addresses of 14 arc4 args with ARC4 address call [0x$CALLADDR]..."
                        return;
                fi
        done

        # Initialize the number of line before CALLADDR to looking for sizes of args
        i=3
        # Retrieve ordered list of size var and append it to $CALLSIZEFILE
        while [[ $($WC -l < "$CALLSIZEFILE") -ne 14 ]]; do
                $GREP -B $i "call.*$CALLADDR" "$DUMPFILE" | $GREP -v "$CALLADDR" | $GREP -Eo "(0x[0-9a-f]+,)" | $GREP -Eo "(0x[0-9a-f]+)" | $GREP -Ev "0x[0-9a-f]{6,}" > "$CALLSIZEFILE"
                i=$(($i + 1))
                if [ $i -eq 10 ]; then
                        echo "[-] Unable to extract sizes of 14 arc4 args with ARC4 address call [0x$CALLADDR]..."
                        return;
                fi
        done

        # For each full address in $CALLADDRFILE and corresponding size in $CALLSIZEFILE
        IFS=$'\n' read -d '' -r -a LISTOFADDR < "$CALLADDRFILE"
        IFS=$'\n' read -d '' -r -a LISTOFSIZE < "$CALLSIZEFILE"
        for (( x = 0; x < ${#LISTOFADDR[*]}; x = x+1 ))
        do
                i=${LISTOFADDR[$x]}
                NBYTES=${LISTOFSIZE[$x]}
        echo -e "\t[$x] Working with var address at offset [$i] ($NBYTES bytes)"
        # Some diferences in assembly.
        # We can have:
        #  mov <adr>,%eax
        #  push 0x<hex>
        #  push %eax
        #  call $CALLADDR
        #
        #  or
        #
        #  push 0x<hex>
        #  push 0x<adr>
        #  call $CALLADDR
        #
        # UPDATE 27/06/2013 :
        # Adding support of objdump format
        # New format supported (Debian 7 x86) :
        #
        #  movl   $0x<hex>,0x4(%esp)
        #
        #  movl   $0x<adr>,(%esp)
        #  call   $CALLADDR
        #
        # UPDATE 18/11/2015 :
        # Adding support of objdump format
        # Ubuntu 14.04 LTS x86_64
        #
        #  mov    $0x<hex>,%esi
        #  mov    $0x<adr>,%edi
        #  callq  $CALLADDR <fork@plt+0x23b>
        #

        # Key is the address with the variable content.
        KEY=$(echo "$i" | $CUT -d 'x' -f 2)

        # A 2 bytes variable (NBYTES > 0) can be found like this: (in STRINGFILE)
        # ---------------X
        # X---------------
        #
        # So we need 2 lines from STRINGFILE to make it all correct. So:
        NLINES=$(( ($NBYTES / 16) +2 ))

        # All line in STRINGFILE starts from 0 to f. So LASTBIT tells me the index in the line to start recording.
        let LASTBYTE="0x${KEY:$((${#KEY}-1))}"

        # Grep all lines needed from STRINGFILE, merge lines.
        STRING=$( $GREP -A $(($NLINES-1)) -E "^ ${KEY:0:$((${#KEY}-1))}0 " "$STRINGFILE" | $AWK '{ print $2$3$4$5}' | $TR '\n' 'T' | $SED -e "s:T::g")

        # Change string to begin in the line index.
        STRING=${STRING:$((2*$LASTBYTE))}
        # Cut the string to the number off bytes of the variable.
        STRING=${STRING:0:$(($NBYTES * 2))}

        # We need to convert to a \x??\x?? structure so:
        FINALSTRING=""
        for ((i = 0; i < $((${#STRING} /2 )); i++)); do
                        FINALSTRING="${FINALSTRING}\x${STRING:$(($i * 2)):2}"
        done

        define_variable
   done
}

# arc4 function is called 14 times in the C code.
# Each call is done with the same args sequence even if their declaration is randomized :
# msg1, date, shll, inlo, xecc, lsto, tst1, chk1, msg2, rlax, opts, text, tst2 and chk2.
function define_variable() {
   case "$j" in
   0)   VAR_MSG1=$FINALSTRING
                VAR_MSG1_Z=$NBYTES;;
   1)   VAR_DATE=$FINALSTRING
                VAR_DATE_Z=$NBYTES;;
   2)   VAR_SHLL=$FINALSTRING
                VAR_SHLL_Z=$NBYTES;;
   3)   VAR_INLO=$FINALSTRING
                VAR_INLO_Z=$NBYTES;;
   4)   VAR_XECC=$FINALSTRING
                VAR_XECC_Z=$NBYTES;;
   5)   VAR_LSTO=$FINALSTRING
                VAR_LSTO_Z=$NBYTES;;
   6)   VAR_TST1=$FINALSTRING
                VAR_TST1_Z=$NBYTES;;
   7)   VAR_CHK1=$FINALSTRING
                VAR_CHK1_Z=$NBYTES;;
   8)   VAR_MSG2=$FINALSTRING
                VAR_MSG2_Z=$NBYTES;;
   9)   VAR_RLAX=$FINALSTRING
                VAR_RLAX_Z=$NBYTES;;
   10)  VAR_OPTS=$FINALSTRING
                VAR_OPTS_Z=$NBYTES;;
   11)  VAR_TEXT=$FINALSTRING
                VAR_TEXT_Z=$NBYTES;;
   12)  VAR_TST2=$FINALSTRING
                VAR_TST2_Z=$NBYTES;;
   13)  VAR_CHK2=$FINALSTRING
                VAR_CHK2_Z=$NBYTES;;
   esac
   j=$(($j + 1))
}


# The password is used in the key function right before first call to arc4.
# So we need the previous call just before the first "call ARC4_CALLADDR" and its args.
# Update 27/06/2013 : Add new objdump format
# Update 18/11/2015 : Simplify extraction
# Update 23/01/2017 : Ignore movb instruction
function extract_password_from_binary(){
        echo "[*] Extracting password..."
        KEY_ADDR=""
        KEY_SIZE=""

        # Initialize the number of line before CALLADDR to watch
        i=5
        while [[ ( -z "$KEY_ADDR" ) || ( -z "$KEY_SIZE" ) ]]; do
                $GREP -B $i -m 1 "call.*$CALLADDR" "$DUMPFILE" | $GREP -v "$CALLADDR" > "$CALLFILE"
                #cat $CALLFILE
                # Adjust these two next line to grep right addr & size value (depending on your architecture)
                KEY_ADDR=$($GREP -B 3 -m 1 "call" "$CALLFILE" | $GREP mov | $GREP -oE "0x[0-9a-z]{6,}+" | $HEAD -n 1)
                KEY_SIZE=$($GREP -B 3 -m 1 "call" "$CALLFILE" | $GREP mov | $GREP -v "$KEY_ADDR" | $GREP -v movb | $GREP -oE "0x[0-9a-z]+" | $HEAD -n 1)
                i=$(($i + 1))
                if [ $i -eq 10 ]; then
                        echo "[-] Error, function call previous first call of arc4() hasn't been identified..."
                        exit_error
                fi
        done
        echo -e "\t[+] PWD address found : [$KEY_ADDR]"
        echo -e "\t[+] PWD size found : [$KEY_SIZE]"

        # Defining the address without 0x.
        KEY=$(echo "$KEY_ADDR" | $CUT -d 'x' -f 2)
        # Like the other NLINES
        NLINES=$(( ($KEY_SIZE / 16) +2 ))
        # Like the other LASTBYTE
        LASTBYTE="0x${KEY:$((${#KEY}-1))}"
        # Extract PWD from STRINGFILE
        STRING=$( $GREP -A $(($NLINES-1)) -E "^ ${KEY:0:$((${#KEY}-1))}0 " "$STRINGFILE" | $AWK '{ print $2$3$4$5}' | $TR '\n' 'T' | $SED -e "s:T::g")
        STRING=${STRING:$((2*$LASTBYTE))}
        STRING=${STRING:0:$(($KEY_SIZE * 2))}
        # Encode / rewrite PWD in the \x??\x?? format
        FINALSTRING=""
        for ((i=0;i<$((${#STRING} /2 ));i++)); do
                FINALSTRING="${FINALSTRING}\x${STRING:$(($i * 2)):2}"
        done
        VAR_PSWD=$FINALSTRING
}

# This function append a generic engine for decrypt from shc project. With out own new variables extracted.
# Rather than execute the source code decrypted, it's printed in stdout.
function generic_file(){
cat > "${TMPBINARY}".c << EOF
#define msg1_z $VAR_MSG1_Z
#define date_z $VAR_DATE_Z
#define shll_z $VAR_SHLL_Z
#define inlo_z $VAR_INLO_Z
#define xecc_z $VAR_XECC_Z
#define lsto_z $VAR_LSTO_Z
#define tst1_z $VAR_TST1_Z
#define chk1_z $VAR_CHK1_Z
#define msg2_z $VAR_MSG2_Z
#define rlax_z $VAR_RLAX_Z
#define opts_z $VAR_OPTS_Z
#define text_z $VAR_TEXT_Z
#define tst2_z $VAR_TST2_Z
#define chk2_z $VAR_CHK2_Z
#define pswd_z $KEY_SIZE

static char msg1 [] = "$VAR_MSG1";
static char date [] = "$VAR_DATE";
static char shll [] = "$VAR_SHLL";
static char inlo [] = "$VAR_INLO";
static char xecc [] = "$VAR_XECC";
static char lsto [] = "$VAR_LSTO";
static char tst1 [] = "$VAR_TST1";
static char chk1 [] = "$VAR_CHK1";
static char msg2 [] = "$VAR_MSG2";
static char rlax [] = "$VAR_RLAX";
static char opts [] = "$VAR_OPTS";
static char text [] = "$VAR_TEXT";
static char tst2 [] = "$VAR_TST2";
static char chk2 [] = "$VAR_CHK2";
static char pswd [] = "$VAR_PSWD";

#define      hide_z     4096

/* rtc.c */

#include <sys/stat.h>
#include <sys/types.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* 'Alleged RC4' */

static unsigned char stte[256], indx, jndx, kndx;

/*
 * Reset arc4 stte.
 */
void stte_0(void)
{
        indx = jndx = kndx = 0;
        do {
                stte[indx] = indx;
        } while (++indx);
}

/*
 * Set key. Can be used more than once.
 */
void key(void * str, int len)
{
        unsigned char tmp, * ptr = (unsigned char *)str;
        while (len > 0) {
                do {
                        tmp = stte[indx];
                        kndx += tmp;
                        kndx += ptr[(int)indx % len];
                        stte[indx] = stte[kndx];
                        stte[kndx] = tmp;
                } while (++indx);
                ptr += 256;
                len -= 256;
        }
}

/*
 * Crypt data.
 */
void arc4(void * str, int len)
{
        unsigned char tmp, * ptr = (unsigned char *)str;
        while (len > 0) {
                indx++;
                tmp = stte[indx];
                jndx += tmp;
                stte[indx] = stte[jndx];
                stte[jndx] = tmp;
                tmp += stte[indx];
                *ptr ^= stte[tmp];
                ptr++;
                len--;
        }
}

/* End of ARC4 */

/*
 * Key with file invariants.
 */
int key_with_file(char * file)
{
        struct stat statf[1];
        struct stat control[1];

        if (stat(file, statf) < 0)
                return -1;

        /* Turn on stable fields */
        memset(control, 0, sizeof(control));
        control->st_ino = statf->st_ino;
        control->st_dev = statf->st_dev;
        control->st_rdev = statf->st_rdev;
        control->st_uid = statf->st_uid;
        control->st_gid = statf->st_gid;
        control->st_size = statf->st_size;
        control->st_mtime = statf->st_mtime;
        control->st_ctime = statf->st_ctime;
        key(control, sizeof(control));
        return 0;
}

void rmarg(char ** argv, char * arg)
{
        for (; argv && *argv && *argv != arg; argv++);
        for (; argv && *argv; argv++)
                *argv = argv[1];
}

// Update 18/11/2015 : Update "mask" casting from "unsigned" to "unsigned long".
int chkenv(int argc)
{
        char buff[512];
        unsigned mask, m;
        int l, a, c;
        char * string;
        extern char ** environ;

        mask  = (unsigned long)chkenv;
        mask ^= (unsigned)getpid() * ~mask;
        sprintf(buff, "x%x", mask);
        string = getenv(buff);
        l = strlen(buff);
        if (!string) {
                /* 1st */
                sprintf(&buff[l], "=%u %d", mask, argc);
                putenv(strdup(buff));
                return 0;
        }
        c = sscanf(string, "%u %d%c", &m, &a, buff);
        if (c == 2 && m == mask) {
                /* 3rd */
                rmarg(environ, &string[-l - 1]);
                return 1 + (argc - a);
        }
        return -1;
}

char * xsh(int argc, char ** argv)
{
        char * scrpt;
        int ret, i, j;
        char ** varg;

        stte_0();
        key(pswd, pswd_z);
        arc4(msg1, msg1_z);
        arc4(date, date_z);
        //if (date[0] && date[0]<time(NULL))
        //        return msg1;
        arc4(shll, shll_z);
        arc4(inlo, inlo_z);
        arc4(xecc, xecc_z);
        arc4(lsto, lsto_z);
        arc4(tst1, tst1_z);
        key(tst1, tst1_z);
        arc4(chk1, chk1_z);
        if ((chk1_z != tst1_z) || memcmp(tst1, chk1, tst1_z))
                return tst1;
        ret = chkenv(argc);
        arc4(msg2, msg2_z);
        if (ret < 0)
                return msg2;
        varg = (char **)calloc(argc + 10, sizeof(char *));
        if (!varg)
                return 0;
        if (ret) {
                arc4(rlax, rlax_z);
                if (!rlax[0] && key_with_file(shll))
                        return shll;
                arc4(opts, opts_z);
                arc4(text, text_z);
                printf("%s",text);
                return 0;
                /*arc4(tst2, tst2_z);
                key(tst2, tst2_z);
                arc4(chk2, chk2_z);
                if ((chk2_z != tst2_z) || memcmp(tst2, chk2, tst2_z))
                        return tst2;
                if (text_z < hide_z) {
                        scrpt = malloc(hide_z);
                        if (!scrpt)
                                return 0;
                        memset(scrpt, (int) ' ', hide_z);
                        memcpy(&scrpt[hide_z - text_z], text, text_z);
                } else {
                        scrpt = text;
                }*/
        } else {
                if (*xecc) {
                        scrpt = malloc(512);
                        if (!scrpt)
                                return 0;
                        sprintf(scrpt, xecc, argv[0]);
                } else {
                        scrpt = argv[0];
                }
        }
        j = 0;
        varg[j++] = argv[0];            /* My own name at execution */
        if (ret && *opts)
                varg[j++] = opts;       /* Options on 1st line of code */
        if (*inlo)
                varg[j++] = inlo;       /* Option introducing inline code */
        varg[j++] = scrpt;              /* The script itself */
        if (*lsto)
                varg[j++] = lsto;       /* Option meaning last option */
        i = (ret > 1) ? ret : 0;        /* Args numbering correction */
        while (i < argc)
                varg[j++] = argv[i++];  /* Main run-time arguments */
        varg[j] = 0;                    /* NULL terminated array */
        execvp(shll, varg);
        return shll;
}

int main(int argc, char ** argv)
{
        argv[1] = xsh(argc, argv);
        return 1;
}
EOF
}

##########################################
## Starting
echo " _   _       _____ _   _      "
echo "| | | |     /  ___| | | |     "
echo "| | | |_ __ \ \`--.| |_| | ___ "
echo "| | | | '_ \ \`--. \  _  |/ __|"
echo "| |_| | | | /\__/ / | | | (__ "
echo " \___/|_| |_\____/\_| |_/\___|"
echo
echo "--- UnSHc - The shc decrypter."
echo "--- Version: $VERSION"
echo "------------------------------"
echo "UnSHc is used to decrypt script encrypted with SHc"
echo "Original idea from Luiz Octavio Duarte (LOD)"
echo "Updated and modernized by Yann CAM"
echo "- SHc   : [http://www.datsi.fi.upm.es/~frosal/]"
echo "- UnSHc : [https://www.asafety.fr/unshc-the-shc-decrypter/]"
echo "------------------------------"
echo

if [ $# -lt 1 ]; then
        echo "[?] Type -h or --help for how to use it"
        clean
        exit 0
fi

# Check the availability of each command needed in this script.
check_binaries

OPTS=$( getopt -o h,a:,d:,s:,o: -l help,arc4:,dumpfile:,stringfile:,outputfile: -- "$@" )
if [ $? != 0 ]; then
        exit_error;
fi

while [ "$#" -gt 0 ] ; do
        case "$1" in
                -h|--help)
                        usage;
                        clean;
                        exit 0;;
                -a|--arc4)
                        echo "[+] ARC4() offset function call address specified [0x$2]";
                        CALLADDR=$2;
                        shift 2;;
                -d|--dumpfile)
                        echo "[+] Object dump file specified [$2]";
                        DUMPFILE=$2;
                        shift 2;;
                -s|--stringfile)
                        echo "[+] String dump file specified [$2]";
                        STRINGFILE=$2;
                        shift 2;;
                -o|--outputfile)
                        echo "[+] Output file name specified [$2]";
                        OUTPUTFILE=$2;
                        shift 2;;
                -*)
                        echo "[-] Unknown option: [$1]" >&2;
                        exit_error;;
                --)
                        shift;
                        break;;
                *)
                        echo "[*] Input file name to decrypt [$1]";
                        BINARY=$1
                        shift 1;;
        esac
done

if [ ! -e "$BINARY" ]; then
        echo "[-] Error, File [$BINARY] not found."
        exit_error
fi
if [ -z "$DUMPFILE" ]; then
         DUMPFILE=$(mktemp /tmp/XXXXXX)
else
        if [ ! -e "$DUMPFILE" ]; then
                echo "[-] Object dump file [$DUMPFILE] not found."
                exit_error;
        fi
fi
if [ -z "$STRINGFILE" ]; then
         STRINGFILE=$(mktemp /tmp/XXXXXX)
else
        if [ ! -e "$STRINGFILE" ]; then
                echo "[-] String dump file [$STRINGFILE] not found."
                exit_error;
        fi
fi

# Fill DUMPFILE and STRINGFILE from objdump of the *.sh.x encrypted script
generate_dump

# Find out the most called function. This function is arc4() and there are 14 calls.
# Then retrieve the data used in each CALLADDR call
c=1
if [ -z "$CALLADDR" ]; then
	# Case when ARC4 offset is unknown and there are multiple candidate
        while [[ $($WC -l < "$CALLSIZEFILE") -ne 14 ]]; do
		extract_arc4_call_addr "$c"
                extract_variables_from_binary
		c=$(($c + 1))
        done
else
	# Case when the ARC4 address is already defined and passed throught args
	extract_variables_from_binary
fi

# Retrieve PWD from function call just before the first CALLADDR call
extract_password_from_binary

# Create a C source code to decrypt *.sh.x file with previously extracted data
generic_file

# Compile C source code to decrypt *.sh.x file
$GCC -o "$TMPBINARY" "${TMPBINARY}".c >/dev/null 2>&1

echo "[*] Executing [$TMPBINARY] to decrypt [${BINARY}]"

chmod +x "$TMPBINARY"
if [ -z "$OUTPUTFILE" ]; then
        echo "[*] Retrieving initial source code in [${BINARY%.sh.x}.sh]"
        $TMPBINARY > "${BINARY%.sh.x}".sh
else
        echo "[*] Retrieving initial source code in [$OUTPUTFILE]"
        $TMPBINARY > "$OUTPUTFILE"
fi

echo "[*] All done!"
clean
exit 0
