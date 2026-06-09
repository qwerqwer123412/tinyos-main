COMPONENT=SimpleWSNAppC

TINYOS_ROOT_DIR?=../..
include $(TINYOS_ROOT_DIR)/Makefile.include


BUILD_EXTRA_DEPS += SimpleWSNMsg.java

CLEAN_EXTRA = SimpleWSNMsg.java *.class

SimpleWSNMsg.java: SimpleWSN.h
	mig java -target=null $(CFLAGS) \
	-java-classname=SimpleWSNMsg \
	SimpleWSN.h simple_wsn_msg -o $@

TINYOS_ROOT_DIR?=../..
include $(TINYOS_ROOT_DIR)/Makefile.include