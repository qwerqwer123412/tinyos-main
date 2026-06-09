import net.tinyos.message.*;
import net.tinyos.packet.*;
import net.tinyos.util.*;

import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

public class SimpleWSNListener implements MessageListener {
    private MoteIF moteIF;
    private static final DateTimeFormatter TIME_FMT =
        DateTimeFormatter.ofPattern("HH:mm:ss");

    public SimpleWSNListener(MoteIF moteIF) {
        this.moteIF = moteIF;
        this.moteIF.registerListener(new SimpleWSNMsg(), this);
    }

    // TelosB / SHT11 raw temperature -> Celsius
    private static double convertTemperature(int rawTemp) {
        return -39.6 + 0.01 * rawTemp;
    }

    // TelosB SHT11 raw humidity -> %RH
    // 일단 단순 2차식 보정 전 기본식 사용
    private static double convertHumidity(int rawHum) {
        return -4.0 + 0.0405 * rawHum - 0.0000028 * rawHum * rawHum;
    }

    // TelosB battery raw ADC -> Volt
    private static double convertBattery(int rawBatt) {
        if (rawBatt == 0) {
            return 0.0;
        }
        return 1.5 * 1023.0 / rawBatt;
    }

    public void messageReceived(int to, Message message) {
        SimpleWSNMsg msg = (SimpleWSNMsg) message;

        String pcTime = LocalTime.now().format(TIME_FMT);

        int node = msg.get_sender();
        int seq = msg.get_seq();

        int rawTemp = msg.get_temperature();
        int rawHum  = msg.get_humidity();
        int rawBatt = msg.get_battery();

        double tempC = convertTemperature(rawTemp);
        double humRH = convertHumidity(rawHum);
        double battV = convertBattery(rawBatt);

        System.out.printf(
            "time %s, node %d, seq %d, "
            + "temperature_raw %d, temperature %.1fC, "
            + "humidity_raw %d, humidity %.1f%%, "
            + "battery_raw %d, battery %.2fV%n",
            pcTime,
            node,
            seq,
            rawTemp, tempC,
            rawHum, humRH,
            rawBatt, battV
        );
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2 || !args[0].equals("-comm")) {
            System.err.println(
                "usage: java SimpleWSNListener -comm serial@/dev/ttyUSB0:telosb"
            );
            return;
        }

        PhoenixSource phoenix =
            BuildSource.makePhoenix(args[1], PrintStreamMessenger.err);
        MoteIF mif = new MoteIF(phoenix);
        new SimpleWSNListener(mif);

        while (true) {
            Thread.sleep(1000);
        }
    }
}