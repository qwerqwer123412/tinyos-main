#include "RadioSenseToLeds.h"

configuration RadioSenseToLedsAppC {}
implementation {
  components MainC, RadioSenseToLedsC as App, LedsC;
  components ActiveMessageC;
  components new AMSenderC(AM_RADIO_SENSE_MSG);
  components new AMReceiverC(AM_RADIO_SENSE_MSG);
  components new TimerMilliC();

  App.Boot -> MainC.Boot;

  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.RadioControl -> ActiveMessageC;
  App.Leds -> LedsC;
  App.MilliTimer -> TimerMilliC;
  App.Packet -> AMSenderC;
}