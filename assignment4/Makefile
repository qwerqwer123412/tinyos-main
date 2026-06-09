COMPONENT=SimpleWSNAppC

TINYOS_ROOT_DIR?=../..

TINYOS_JAVA_JAR=/home/nsl/tinyos-main/tools/tinyos/java/tinyos.jar

CFLAGS += -DCC2420_DEF_CHANNEL=26
CFLAGS += -DCC2420_DEF_RFPOWER=31
CFLAGS += -DWSN_RADIO_CHANNEL=26
CFLAGS += -DWSN_RADIO_TX_POWER=31

CLEAN_EXTRA = SimpleWSNMsg.java *.class

include $(TINYOS_ROOT_DIR)/Makefile.include

telosb: SimpleWSNCmd.class

SimpleWSNMsg.java: SimpleWSN.h
	nescc-mig java $(CFLAGS) \
	-java-classname=SimpleWSNMsg \
	SimpleWSN.h simple_wsn_msg -o $@

SimpleWSNCmd.class: SimpleWSNCmd.java SimpleWSNMsg.java
	javac -cp .:$(TINYOS_JAVA_JAR) \
	SimpleWSNMsg.java SimpleWSNCmd.java