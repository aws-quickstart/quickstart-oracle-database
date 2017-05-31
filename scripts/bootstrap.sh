#!/bin/bash -e
# Oracle Database Bootstraping
# author: sancard@amazon.com
# NOTE: This requires GNU getopt.  On Mac OS X and FreeBSD you must install GNU getopt

# Configuration
PROGRAM='Oracle Database'

##################################### Functions
function checkos() {
    platform='unknown'
    unamestr=`uname`
    if [[ "${unamestr}" == 'Linux' ]]; then
        platform='linux'
    else
        echo "[WARNING] This script is not supported on MacOS or freebsd"
        exit 1
    fi
}

function usage() {
echo "$0 <usage>"
echo " "
echo "options:"
echo -e "-h, --help \t show options for this script"
echo -e "-v, --verbose \t specify to print out verbose bootstrap info"
echo -e "--params_file \t specify the params_file to read (--params_file /tmp/orcl-setup.txt)"
echo -e "--primary \t specify for primary host"
echo -e "--standby \t specify for standby host"
}

function chkstatus() {
    if [ $? -eq 0 ]
    then
        echo "Script [PASS]"
    else
        echo "Script [FAILED]" >&2
        exit 1
    fi
}

function configOL67HVM() {
    sed -i 's/1024/16384/g' /etc/security/limits.d/90-nproc.conf
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
}

function configRHEL72HVM() {
    sed -i 's/4096/16384/g' /etc/security/limits.d/20-nproc.conf
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
    yum-config-manager --enable rhui-REGION-rhel-server-extras rhui-REGION-rhel-server-optional
    setenforce Permissive
}

function install_packages() {
    echo "[INFO] Calling: yum install -y $@"
    yum install -y $@ > /dev/null
}
##################################### Functions

# Call checkos to ensure platform is Linux
checkos

ARGS=`getopt -o hv -l help,verbose,params_file:,primary,standby -n $0 -- "$@"`
eval set -- "${ARGS}"

if [ $# == 1 ]; then
    echo "No input provided! type ($0 --help) to see usage help" >&2
    exit 2
fi

# extract options and their arguments into variables.
while true; do
    case "$1" in
        -v|--verbose)
            echo "[] DEBUG = ON"
            VERBOSE=true;
            shift
            ;;
        --params_file)
            echo "[] PARAMS_FILE = $2"
            PARAMS_FILE="$2";
            shift 2
            ;;
        --primary)
            echo "[] HOST_TYPE = PRIMARY"
            HOST_TYPE='PRIMARY';
            shift
            ;;
        --standby)
            echo "[] HOST_TYPE = STANDBY"
            HOST_TYPE='STANDBY';
            shift
            ;;
        --)
            break
            ;;
        *)
            break
            ;;
    esac
done

if [[ ${HOST_TYPE} != 'PRIMARY' && ${HOST_TYPE} != 'STANDBY' ]]; then
    echo "You must specify --primary or --standby to indicate the host being configured."
    exit 1
fi

## Set an initial value
QS_S3_URL='NONE'
QS_S3_BUCKET='NONE'
QS_S3_KEY_PREFIX='NONE'
QS_S3_SCRIPTS_PATH='NONE'
INSTALLER_S3_BUCKET='NONE'
OS_CODE='NONE'
SGA_VALUE='NONE'
SHMALL_VALUE='NONE'
SHMMAX_VALUE='NONE'
DATABASE_PASS='NONE'
ASM_PASS='NONE'
CHARACTER_SET='NONE'
DATABASE_PORT='NONE'
PRIMARY_NAME='NONE'
STANDBY_NAME='NONE'
PRIMARY_IP='NONE'
STANDBY_IP='NONE'
OSB_CHOICE='NONE'
OSB_AWS_BUCKET='NONE'
OSB_AWS_KEY='NONE'
OSB_AWS_SECRET='NONE'
OSB_OTN_USER='NONE'
OSB_OTN_PASS='NONE'

if [ -f ${PARAMS_FILE} ]; then
    QS_S3_URL=`grep 'QuickStartS3URL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_BUCKET=`grep 'QSS3Bucket' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    QS_S3_KEY_PREFIX=`grep 'QSS3KeyPrefix' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    INSTALLER_S3_BUCKET=`grep 'InstallBucketName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OS_CODE=`grep 'Code' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    SGA_VALUE=`grep 'SGA' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    SHMALL_VALUE=`grep 'SHMALL' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    SHMMAX_VALUE=`grep 'SHMMAX' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_PASS=`grep 'DatabasePass' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    ASM_PASS=`grep 'AsmPass' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    CHARACTER_SET=`grep 'CharacterSet' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    DATABASE_PORT=`grep 'DatabasePort' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    PRIMARY_NAME=`grep 'DatabaseName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    STANDBY_NAME=`grep 'StandbyName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    PRIMARY_IP=`grep 'PrimaryIPAddress' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    STANDBY_IP=`grep 'StandbyIPAddress' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_CHOICE=`grep 'OSBInstall' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_AWS_BUCKET=`grep 'OSBBName' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_AWS_KEY=`grep 'OSBKey' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_AWS_SECRET=`grep 'OSBSecret' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_OTN_USER=`grep 'OSBOTN' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`
    OSB_OTN_PASS=`grep 'OSBPass' ${PARAMS_FILE} | awk -F'|' '{print $2}' | sed -e 's/^ *//g;s/ *$//g'`

    # Strip leading slash
    if [[ ${QS_S3_KEY_PREFIX} == /* ]];then
          echo "Removing leading slash"
          QS_S3_KEY_PREFIX=$(echo ${QS_S3_KEY_PREFIX} | sed -e 's/^\///')
    fi

    # Format S3 script path
    QS_S3_SCRIPTS_PATH="${QS_S3_URL}/${QS_S3_BUCKET}/${QS_S3_KEY_PREFIX}/scripts"
else
    echo "Paramaters file not found or accessible."
    exit 1
fi

if [[ ${VERBOSE} == 'true' ]]; then
    echo "QS_S3_URL = ${QS_S3_URL}"
    echo "QS_S3_BUCKET = ${QS_S3_BUCKET}"
    echo "QS_S3_KEY_PREFIX = ${QS_S3_KEY_PREFIX}"
    echo "QS_S3_SCRIPTS_PATH = ${QS_S3_SCRIPTS_PATH}"
    echo "INSTALLER_S3_BUCKET = ${INSTALLER_S3_BUCKET}"
    echo "OS_CODE = ${OS_CODE}"
    echo "SGA_VALUE = ${SGA_VALUE}"
    echo "SHMALL_VALUE = ${SHMALL_VALUE}"
    echo "SHMMAX_VALUE = ${SHMMAX_VALUE}"
    echo "DATABASE_PASS = ${DATABASE_PASS}"
    echo "ASM_PASS = ${ASM_PASS}"
    echo "CHARACTER_SET = ${CHARACTER_SET}"
    echo "DATABASE_PORT = ${DATABASE_PORT}"
    echo "PRIMARY_NAME = ${PRIMARY_NAME}"
    echo "STANDBY_NAME = ${STANDBY_NAME}"
    echo "PRIMARY_IP = ${PRIMARY_IP}"
    echo "STANDBY_IP = ${STANDBY_IP}"
    echo "OSB_CHOICE = ${OSB_CHOICE}"
    echo "OSB_AWS_BUCKET = ${OSB_AWS_BUCKET}"
    echo "OSB_AWS_KEY = ${OSB_AWS_KEY}"
    echo "OSB_AWS_SECRET = ${OSB_AWS_SECRET}"
    echo "OSB_OTN_USER = ${OSB_OTN_USER}"
    echo "OSB_OTN_PASS = ${OSB_OTN_PASS}"
fi


#############################################################
# Start Oracle Database Setup
#############################################################

# START SETUP script
sed -i s/QS_DATABASE_PASS/${DATABASE_PASS}/g /tmp/*.rsp /tmp/*.sql /tmp/*.cmd
sed -i s/QS_ASM_PASS/${ASM_PASS}/g /tmp/*.rsp /tmp/*.sql /tmp/*.cmd
sed -i s/QS_PRIMARY_NAME/${PRIMARY_NAME}/g /tmp/*.ora /tmp/*.rsp /tmp/*.sql /tmp/*.cmd
sed -i s/QS_STANDBY_NAME/${STANDBY_NAME}/g /tmp/*.ora /tmp/*.rsp /tmp/*.sql /tmp/*.cmd
sed -i s/QS_CHARACTER_SET/${CHARACTER_SET}/g /tmp/*.rsp
sed -i s/QS_SGA_VALUE/${SGA_VALUE}/g /tmp/*.rsp
sed -i s/QS_DATABASE_PORT/${DATABASE_PORT}/g /tmp/*.ora /tmp/*.rsp /tmp/*.sql
sed -i s/QS_PRIMARY_IP/${PRIMARY_IP}/g /tmp/*.ora /tmp/*.sql
sed -i s/QS_STANDBY_IP/${STANDBY_IP}/g /tmp/*.ora /tmp/*.sql
if [[ ${OS_CODE} == 'OL67HVM' ]]; then
    configOL67HVM
elif [[ ${OS_CODE} == 'RHEL72HVM' ]]; then
    configRHEL72HVM
fi
# Update Kernel parameters to Oracle Documentation recommended values
cp /etc/sysctl.conf /etc/sysctl.conf_backup
cat /etc/sysctl.conf | grep -v shmall | grep -v shmmax >/etc/sysctl.conf_txt
mv -f /etc/sysctl.conf_txt /etc/sysctl.conf
echo '#input parameters from AWS Quick Start' >>/etc/sysctl.conf
echo 'fs.file-max = 6815744' >>/etc/sysctl.conf
echo 'kernel.sem = 250 32000 100 128' >>/etc/sysctl.conf
echo 'kernel.shmmni = 4096' >>/etc/sysctl.conf
echo kernel.shmall = ${SHMALL_VALUE} >>/etc/sysctl.conf
echo kernel.shmmax = ${SHMMAX_VALUE} >>/etc/sysctl.conf
echo 'net.core.rmem_default = 262144' >>/etc/sysctl.conf
echo 'net.core.rmem_max = 4194304' >>/etc/sysctl.conf
echo 'net.core.wmem_default = 262144' >>/etc/sysctl.conf
echo 'net.core.wmem_max = 1048576' >>/etc/sysctl.conf
echo 'fs.aio-max-nr = 1048576' >>/etc/sysctl.conf
echo 'net.ipv4.ip_local_port_range = 9000 65500' >>/etc/sysctl.conf
# Activate Kernel parameter updated
/sbin/sysctl -p
echo QS_Kernel_Parms_SETUP
# Update user limit for Oracle limits recommended values
cp /etc/security/limits.conf /etc/security/limits.conf_backup
cat /etc/security/limits.conf | grep -v End >/etc/security/limits.conf_txt
mv -f /etc/security/limits.conf_txt /etc/security/limits.conf
echo '#input parameters from Cloudformation' >>/etc/security/limits.conf
echo 'oracle   soft   nofile    1024' >>/etc/security/limits.conf
echo 'oracle   hard   nofile    65536' >>/etc/security/limits.conf
echo 'oracle   soft   nproc    16384' >>/etc/security/limits.conf
echo 'oracle   hard   nproc    16384' >>/etc/security/limits.conf
echo 'oracle   soft   stack    10240' >>/etc/security/limits.conf
echo 'oracle   hard   stack    32768' >>/etc/security/limits.conf
echo '# End of file' >>/etc/security/limits.conf
echo QS_oracle_user_limits
# Create Oracle user
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
useradd -u 54321 -g oinstall -G dba,oper oracle
echo QS_Oracle_user
# Create the /u01 filesystem, and Oracle paths and update fstab
mkdir -p /u01
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdb
sync
echo DEBUGfdisk
mkfs -t ext4 /dev/xvdb1
echo '/dev/xvdb1 /u01   ext4    defaults,noatime  1   1'>>/etc/fstab
mount /u01
mkdir -p /u01/app/oracle/product/12.1.0.2/db_1
mkdir -p /u01/app/oracle/product/12.1.0.2/grid
mkdir -p /u01/install
if df -k | grep u01 ; then
    echo "QS_U01_FS|SUCCESS"
else
    echo "QS_U01_FS|FAILURE"
    exit 1
fi
# Move installer parameter files .rsp  to /u01/install
mv /tmp/*.rsp /u01/install/.
# Create and mount a Shared Filesystem between the machines to exchange controlfile and init files
install_packages nfs-utils nfs-utils-lib
if [[ ${HOST_TYPE} == 'PRIMARY' ]]; then
    echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdy
    sync
    mkdir /shared
    chmod 777 /shared
    mkfs -t ext4 /dev/xvdy1
    echo '/dev/xvdy1 /shared   ext4    defaults,noatime  1   1'>>/etc/fstab
    chmod 777 /shared
    echo /shared ${STANDBY_IP}"(rw)" >>/etc/exports
    service rpcbind start
    service nfs start
    service nfslock start
    mount /shared
    exportfs -a
elif [[ ${HOST_TYPE} == 'STANDBY' ]]; then
    service rpcbind start
    service nfs start
    service nfslock start
    mkdir /shared
    chmod 777 /shared
    mount -t nfs ${PRIMARY_IP}:/shared /shared
fi
if df -k | grep shared ; then
    echo "QS_SHARED_FS|SUCCESS"
else
    echo "QS_SHARED_FS|FAILURE"
    exit 1
fi
echo QS_File_Systems_Mounted
# Download Oracle Binaries
echo QS_BEGIN_media_download
aws s3 cp s3://${INSTALLER_S3_BUCKET}/linuxamd64_12102_database_1of2.zip /u01/install/linuxamd64_12102_database_1of2.zip >> /tmp/download.log
aws s3 cp s3://${INSTALLER_S3_BUCKET}/linuxamd64_12102_database_2of2.zip /u01/install/linuxamd64_12102_database_2of2.zip >> /tmp/download.log
aws s3 cp s3://${INSTALLER_S3_BUCKET}/linuxamd64_12102_grid_1of2.zip /u01/install/linuxamd64_12102_grid_1of2.zip >> /tmp/download.log
aws s3 cp s3://${INSTALLER_S3_BUCKET}/linuxamd64_12102_grid_2of2.zip /u01/install/linuxamd64_12102_grid_2of2.zip >> /tmp/download.log
aws s3 cp s3://${INSTALLER_S3_BUCKET}/oracleasm-support-2.1.8-1.el6.x86_64.rpm /u01/install/oracleasm-support-2.1.8-1.el6.x86_64.rpm >> /tmp/download.log
aws s3 cp s3://${INSTALLER_S3_BUCKET}/oracleasmlib-2.0.4-1.el6.x86_64.rpm /u01/install/oracleasmlib-2.0.4-1.el6.x86_64.rpm >> /tmp/download.log
echo QS_END_media_download
# Copy files from shared Filesystem from PRIMARY to STANDBY instance
cd /u01/install
if [[ ${HOST_TYPE} == 'STANDBY' ]]; then
    mkdir /u01/install/config
    cp /shared/stby.* /u01/install/config/.
    cp /shared/tns* /u01/install/config/.
    cp /shared/orapw* /u01/install/config/.
fi
echo QS_FilesDownloaded
# Unzip Oracle Binaries for Installation
unzip -q linuxamd64_12102_database_1of2.zip
unzip -q linuxamd64_12102_database_2of2.zip
unzip -q linuxamd64_12102_grid_1of2.zip
unzip -q linuxamd64_12102_grid_2of2.zip
cd /u01/install
if ls -l /u01/install/database/runInstaller ; then
    echo "QS_ORA_INSTALL_UNZIP|SUCCESS"
else
    echo "QS_ORA_INSTALL_UNZIP|FAILURE"
    exit 1
fi
if ls -l /u01/install/grid/runInstaller ; then
    echo "QS_GRID_INSTALL_UNZIP|SUCCESS"
else
    echo "QS_GRID_INSTALL_UNZIP|FAILURE"
    exit 1
fi
# Install ASM Modules
if [[ ${OS_CODE} == 'OL67HVM' ]]; then
    install_packages kmod-oracleasm
elif [[ ${OS_CODE} == 'RHEL72HVM' ]]; then
    yum install -y kmod-oracleasm-2.0.8-15.el7.x86_64
fi
rpm -Uvh oracleasm-support-2.1.8-1.el6.x86_64.rpm
rpm -Uvh oracleasmlib-2.0.4-1.el6.x86_64.rpm
# Change permission to oracle:oinstall for filesystem /u01
chown -R oracle:oinstall /u01
chmod -R 775 /u01
# Configure oracleasm module and initialize it
oracleasm configure -u oracle -g dba -b -s y -e
oracleasm init
# Make partitions to the ASM RECO and DATA disks
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdc
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdd
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvde
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdf
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdg
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdh
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdi
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdj
echo -e 'o\nn\np\n1\n\n\nw' | fdisk /dev/xvdk
sync
# Updated DISK headers to assign an ASM DISKGROUP
oracleasm createdisk RECO1 /dev/xvdc1
oracleasm createdisk RECO2 /dev/xvdd1
oracleasm createdisk RECO3 /dev/xvde1
oracleasm createdisk DATA1 /dev/xvdf1
oracleasm createdisk DATA2 /dev/xvdg1
oracleasm createdisk DATA3 /dev/xvdh1
oracleasm createdisk DATA4 /dev/xvdi1
oracleasm createdisk DATA5 /dev/xvdj1
oracleasm createdisk DATA6 /dev/xvdk1
# Restart oracleasm
oracleasm init
# Install Kernel packages needed to install Oracle and to have a Graphic interface needed for Oracle Java tools
YUM_PACKAGES=(
    xorg-x11-xauth.x86_64
    xorg-x11-server-utils.x86_64
    dbus-x11.x86_64
    binutils
    compat-libcap1
    gcc
    gcc-c++
    glibc
    glibc.i686
    glibc-devel
    glibc-devel.i686
    ksh
    libgcc
    libgcc.i686
    libstdc++
    libstdc++.i686
    libstdc++-devel
    libstdc++-devel.i686
    libaio
    libaio.i686
    libaio-devel
    libaio-devel.i686
    libXext
    libXext.i686
    libXtst
    libXtst.i686
    libX11
    libX11.i686
    libXau
    libXau.i686
    libxcb
    libxcb.i686
    libXi
    libXi.i686
    make
    sysstat
    unixODBC
    unixODBC-devel
    java
    compat-libstdc++-33
)
install_packages ${YUM_PACKAGES[@]}
# Update Oracle user profile
echo 'export TMP=/tmp' >>/home/oracle/.bash_profile
echo 'export TMPDIR=/tmp' >>/home/oracle/.bash_profile
echo 'export ORACLE_BASE=/u01/app/oracle' >>/home/oracle/.bash_profile
echo 'export ORACLE_HOME=/u01/app/oracle/product/12.1.0.2/db_1' >>/home/oracle/.bash_profile
if [[ ${HOST_TYPE} == 'PRIMARY' ]]; then
    echo export ORACLE_SID=${PRIMARY_NAME} >>/home/oracle/.bash_profile
elif [[ ${HOST_TYPE} == 'STANDBY' ]]; then
    echo export ORACLE_SID=${STANDBY_NAME} >>/home/oracle/.bash_profile
fi
echo 'export PATH=/usr/sbin:$PATH' >>/home/oracle/.bash_profile
echo 'export PATH=/u01/app/oracle/product/12.1.0.2/db_1/bin:$PATH' >>/home/oracle/.bash_profile
echo 'export LD_LIBRARY_PATH=/u01/app/oracle/product/12.1.0.2/db_1/lib:/lib:/usr/lib' >>/home/oracle/.bash_profile
echo 'export CLASSPATH=/u01/app/oracle/product/12.1.0.2/db_1/jlib:/u01/app/oracle/product/12.1.0.2/db_1/rdbms/jlib' >>/home/oracle/.bash_profile
# Make a SWAP space available and update fsta
mkswap /dev/xvdx
swapon /dev/xvdx
echo '/dev/xvdx    swap      swap    defaults       0 0'>>/etc/fstab
# Update permission for Oracle user to sudo and to ssh
mkdir -p /home/oracle/.ssh
cp /home/ec2-user/.ssh/authorized_keys /home/oracle/.ssh/.
chown oracle:dba /home/oracle/.ssh /home/oracle/.ssh/authorized_keys
chmod 600 /home/oracle/.ssh/authorized_keys
echo 'oracle ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
sed -i 's/requiretty/!requiretty/g' /etc/sudoers
# Prepare and execute oracleexec
touch /tmp/oracleexec.log
chown oracle:dba /tmp/oracleexec.*
echo QS_BEGIN_oracleexec.sh
if [[ ${HOST_TYPE} == 'PRIMARY' ]]; then
    sudo su -l oracle -c '/tmp/oracleexec.sh ${0} ${1} ${2}' -- ${ASM_PASS} ${DATABASE_PORT} ${PRIMARY_NAME} &> /tmp/oracleexec.log
elif [[ ${HOST_TYPE} == 'STANDBY' ]]; then
    sudo su -l oracle -c '/tmp/oracleexec-sb.sh ${0} ${1} ${2} ${3} ${4}' -- ${DATABASE_PASS} ${ASM_PASS} ${DATABASE_PORT} ${PRIMARY_NAME} ${STANDBY_NAME} &> /tmp/oracleexec.log
fi
echo QS_END_oracleexec.sh
# Check ASM instance Status
if ps -ef | grep smon | grep ASM; then
    echo "QS_ASM_INSTANCE|SUCCESS"
else
    echo "QS_ASM_INSTANCE|FAILURE"
    exit 1
fi
# Check Database instance Status
if ps -ef | grep smon | grep -v ASM | grep -v grep; then
    echo "QS_DATABASE_INSTANCE|SUCCESS"
else
    echo "QS_DATABASE_INSTANCE|FAILURE"
    exit 1
fi
# Check health of Primary and standby Databases, and Data Guard configuration
if [[ ${HOST_TYPE} == 'PRIMARY' ]]; then
    if grep -q "QS_PRIMARY_DATABASE_SETUP|SUCCESS" /tmp/status.log; then
        echo "QS_PRIMARY_DATABASE_SETUP|SUCCESS"
    else
        echo "QS_PRIMARY_DATABASE_SETUP|FAILURE"
        exit 1
    fi
elif [[ ${HOST_TYPE} == 'STANDBY' ]]; then
    if grep -q "Physical standby database" /tmp/dgmgrl.conf; then
        echo "QS_DG_BROKER_CONFIGURED|SUCCESS"
    else
        echo "QS_DG_BROKER_CONFIGURED|FAILURE"
        exit 1
    fi
    if grep -q "QS_PHYSICAL_STANDBY|SUCCESS" /tmp/status.log; then
        echo "QS_PHYSICAL_STANDBY|SUCCESS"
    else
        echo "QS_PHYSICAL_STANDBY|FAILURE"
        exit 1
    fi
fi
# Install Oracle Secure Backup and Configure it
chown oracle:dba /tmp/osb*
echo QS_BEGIN_osb.sh
sudo su -l oracle -c '/tmp/osb.sh ${0} ${1} ${2} ${3} ${4} ${5} ${6} ${7} ${8}' -- ${OSB_CHOICE} ${HOST_TYPE} ${PRIMARY_NAME} ${INSTALLER_S3_BUCKET} ${OSB_AWS_BUCKET} ${OSB_AWS_KEY} ${OSB_AWS_SECRET} ${OSB_OTN_USER} ${OSB_OTN_PASS} &> /tmp/osb.log
echo QS_END_osb.sh
# Change backup permissions of sudoers
sed -i 's/!requiretty/requiretty/g' /etc/sudoers
# Copy files from PRIMARY instance to Shared Filesystem
if [[ ${HOST_TYPE} == 'PRIMARY' ]]; then
    cp /tmp/stby.ctl /shared/.
    cp /tmp/stby.ora /shared/.
    cp /u01/app/oracle/product/12.1.0.2/db_1/network/admin/tnsnames.ora /shared/.
    cp /u01/app/oracle/product/12.1.0.2/db_1/dbs/orapw${PRIMARY_NAME} /shared/.
    chown -R oracle:oinstall /shared
    chmod 777 -R /shared/
fi
# Remove passwords from files
sed -i s/${DATABASE_PASS}/xxxxx/g /u01/install/*.rsp /var/log/cloud-init.log /tmp/*.sql
sed -i s/${ASM_PASS}/xxxxx/g /u01/install/*.rsp /var/log/cloud-init.log /tmp/*.sql
echo "QS_END_OF_SETUP_SH"
# END SETUP script

# Remove files used in bootstrapping
rm ${PARAMS_FILE}

echo "Finished AWS Quick Start Bootstrapping"
