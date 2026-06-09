//configuration code
#include "SimpleWSN.h"

configuration SimpleWSNAppC {}
implementation {
  components MainC, SimpleWSNC as App, LedsC;
  components ActiveMessageC;
  components new AMSenderC(AM_SIMPLE_WSN_MSG);
  components new AMReceiverC(AM_SIMPLE_WSN_MSG);
  components new TimerMilliC();
  components LocalTimeMilliC;

  components new SensirionSht11C() as TempHumSensor;
  components new VoltageC() as VoltageSensor;

  App.Boot -> MainC.Boot;
  App.RadioControl -> ActiveMessageC;

  App.AMSend -> AMSenderC;
  App.Receive -> AMReceiverC;
  App.Packet -> AMSenderC;

  App.Leds -> LedsC;
  App.MilliTimer -> TimerMilliC;
  App.LocalTime -> LocalTimeMilliC;

  App.TempRead -> TempHumSensor.Temperature;
  App.HumRead  -> TempHumSensor.Humidity;
  App.BattRead -> VoltageSensor;
}