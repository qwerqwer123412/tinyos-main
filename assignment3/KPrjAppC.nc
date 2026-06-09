#include "KPrj.h"

configuration KPrjAppC {}
implementation {
  components MainC;
  components ActiveMessageC;
  components CC2420ActiveMessageC;
  components KPrjC as App;

  components new AMSenderC(AM_KPRRMSG);
  components new AMReceiverC(AM_KPRRMSG);

  components new TimerMilliC() as SendTimer;
  components new TimerMilliC() as FinishTimer;
  components new TimerMilliC() as LedTimer;

  components LedsC;

  components PrintfC;
  components SerialStartC;

  App.Boot -> MainC.Boot;
  App.AMControl -> ActiveMessageC;

  App.AMSend -> AMSenderC;
  App.Receive -> AMReceiverC;
  App.Packet -> AMSenderC;

  App.SendTimer -> SendTimer;
  App.FinishTimer -> FinishTimer;
  App.LedTimer -> LedTimer;

  App.CC2420Packet -> CC2420ActiveMessageC.CC2420Packet;
  App.Leds -> LedsC;
}