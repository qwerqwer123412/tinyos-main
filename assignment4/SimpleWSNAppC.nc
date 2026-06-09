#include "SimpleWSN.h"

configuration SimpleWSNAppC {}
implementation {
  components MainC, SimpleWSNC as App, LedsC;

  components ActiveMessageC;
  components SerialActiveMessageC;

  components new AMSenderC(AM_SIMPLE_WSN_MSG) as RadioSender;
  components new AMReceiverC(AM_SIMPLE_WSN_MSG) as RadioReceiver;

  components new SerialAMSenderC(AM_SIMPLE_WSN_MSG) as SerialSender;
  components new SerialAMReceiverC(AM_SIMPLE_WSN_MSG) as SerialReceiver;

  components new TimerMilliC() as MilliTimer;
  components new TimerMilliC() as ReplyTimer;

  components LocalTimeMilliC;

  components new SensirionSht11C() as TempHumSensor;
  components new VoltageC() as VoltageSensor;

  App.Boot -> MainC.Boot;

  App.RadioControl -> ActiveMessageC;
  App.SerialControl -> SerialActiveMessageC;

  App.RadioSend -> RadioSender;
  App.RadioReceive -> RadioReceiver;
  App.RadioPacket -> RadioSender;

  App.SerialSend -> SerialSender;
  App.SerialReceive -> SerialReceiver;
  App.SerialPacket -> SerialSender;

  App.MilliTimer -> MilliTimer;
  App.ReplyTimer -> ReplyTimer;

  App.Leds -> LedsC;
  App.LocalTime -> LocalTimeMilliC;

  App.TempRead -> TempHumSensor.Temperature;
  App.HumRead  -> TempHumSensor.Humidity;
  App.BattRead -> VoltageSensor;
}