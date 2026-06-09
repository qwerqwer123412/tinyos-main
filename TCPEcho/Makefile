COMPONENT=TCPEchoC

# uncomment this for network programming support
# BOOTLOADER=tosboot

# radio opts
#CFLAGS += -DCC2420_DEF_CHANNEL=15
PFLAGS += -DCC2420_DEF_CHANNEL=26
PFLAGS += -DWSN_RADIO_CHANNEL=26
CFLAGS += -DCC2420_DEF_RFPOWER=31
CFLAGS += -DWSN_RADIO_TX_POWER=31
DEFAULT_LOCAL_GROUP = 0xCA
################################################################################
### Set the addressing scheme
################################################################################

# Use static IPv6 addresses: node N => fd00:23:42:1::N.
PFLAGS += -DIN6_PREFIX=\"fd00:23:42:1::\"
# Leave IN6_PREFIX undefined to use DHCPv6 address assignment.
# Use BLIP Neighbor Discovery to autoconfigure an address
PFLAGS += -DBLIP_ADDR_AUTOCONF=0
# Use RPL and prefix information in DIO messages to autoconfigure an address
PFLAGS += -DRPL_ADDR_AUTOCONF=0

################################################################################
### Configure BLIP
################################################################################

# Configure the Neighbor Discovery mechanism
PFLAGS += -DBLIP_SEND_ROUTER_SOLICITATIONS=1
PFLAGS += -DBLIP_SEND_ROUTER_ADVERTISEMENTS=0

# Configure the number of times BLIP tries to send a packet and how long it
# waits between attempts
#PFLAGS += -DBLIP_L2_RETRIES=5
#PFLAGS += -DBLIP_L2_DELAY=103

# Configure how many of the 6LoWPAN headers we support
#PFLAGS += -DLIB6LOWPAN_FULL=1

# Configure the header compression for 6LoWPAN
PFLAGS += -DLIB6LOWPAN_HC_VERSION=6

# Keep statistics about various BLIP/IPv6 parameters. See BlipStatistics.h
#PFLAGS += -DBLIP_STATS
#PFLAGS += -DBLIP_STATS_IP_MEM

# Bigger link-layer send/fragment pool. A TCP (HTTP) exchange bursts several
# packets at once; with the shared default (12) the node runs out of send
# buffers under repeated curl requests, can't even send RPL control traffic,
# drops off the DODAG and wedges permanently. 20 gives enough headroom that it
# recovers instead. (PppRouter can't afford this; it keeps the default 12.)
PFLAGS += -DN_FRAGMENTS=20

################################################################################
### Configure RPL
################################################################################

# Include the RPL layer if set to 1
PFLAGS += -DRPL_ROUTING=1

# If set keep routing information in each node. If not the root must keep all
# routing information.
PFLAGS += -DRPL_STORING_MODE=1

# Choose the objective function RPL should use
PFLAGS += -DRPL_OF_0=1
PFLAGS += -DRPL_OF_MRHOF=0

################################################################################
### Configure LPL
################################################################################

#PFLAGS += -DLOW_POWER_LISTENING
#PFLAGS += -DLPL_SLEEP_INTERVAL=512
#PFLAGS += -DLPL_DEF_LOCAL_WAKEUP=512
#PFLAGS += -DLPL_DEF_REMOTE_WAKEUP=512

################################################################################
### Configure printf() output
################################################################################

#PFLAGS += -DNEW_PRINTF_SEMANTICS -DPRINTFUART_ENABLED

################################################################################
### Configure this application
################################################################################

# If this is set, motes will send debugging information to the address listed.
#PFLAGS += -DREPORT_DEST=\"2001:470:1f04:56d::64\"



GOALS += blip rpl

TINYOS_ROOT_DIR?=../..
include $(TINYOS_ROOT_DIR)/Makefile.include
