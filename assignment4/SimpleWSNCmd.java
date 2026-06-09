import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import net.tinyos.message.*;
import net.tinyos.packet.*;
import net.tinyos.util.*;

public class SimpleWSNCmd implements MessageListener {
    private static final int BASE_STATION_ID = 1;
    private static final int NODE_BROADCAST = 0xFFFF;

    private static final short TYPE_DATA = 1;
    private static final short TYPE_CMD  = 2;
    private static final short TYPE_RESP = 3;

    private static final short CMD_GET_LED      = 1;
    private static final short CMD_SET_LED      = 2;
    private static final short CMD_GET_VOLTAGE  = 3;
    private static final short CMD_GET_TEMP     = 4;
    private static final short CMD_GET_CHANNEL  = 5;
    private static final short CMD_GET_TX_POWER = 6;

    private MoteIF moteIF;
    private int seq = 0;

    public SimpleWSNCmd(String source) {
        if (source == null) {
            moteIF = new MoteIF(PrintStreamMessenger.err);
        } else {
            PhoenixSource phoenix =
                    BuildSource.makePhoenix(source, PrintStreamMessenger.err);
            moteIF = new MoteIF(phoenix);
        }

        moteIF.registerListener(new SimpleWSNMsg(), this);
    }

    private static void usage() {
        System.out.println("Usage:");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 all get-temp");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 3 get-temp");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 sensor 3 get-voltage");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 sensors 2,3,5 get-led");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 each get-channel");
        System.out.println("  java SimpleWSNCmd -comm sf@localhost:9002 4 set-led 7");
        System.exit(1);
    }

    private static short parseCommand(String s) {
        if (s.equals("get-led")) {
            return CMD_GET_LED;
        }
        if (s.equals("set-led")) {
            return CMD_SET_LED;
        }
        if (s.equals("get-voltage")) {
            return CMD_GET_VOLTAGE;
        }
        if (s.equals("get-temp")) {
            return CMD_GET_TEMP;
        }
        if (s.equals("get-channel")) {
            return CMD_GET_CHANNEL;
        }
        if (s.equals("get-tx-power")) {
            return CMD_GET_TX_POWER;
        }

        usage();
        return 0;
    }

    private static String cmdName(int cmd) {
        switch (cmd) {
            case CMD_GET_LED:
                return "get-led";
            case CMD_SET_LED:
                return "set-led";
            case CMD_GET_VOLTAGE:
                return "get-voltage";
            case CMD_GET_TEMP:
                return "get-temp";
            case CMD_GET_CHANNEL:
                return "get-channel";
            case CMD_GET_TX_POWER:
                return "get-tx-power";
            default:
                return "unknown";
        }
    }

    private static List<Integer> parseTargets(String[] args, int[] indexRef) {
        List<Integer> targets = new ArrayList<Integer>();
        int index = indexRef[0];

        if (index >= args.length) {
            usage();
        }

        String targetArg = args[index];

        if (targetArg.equals("all")) {
            targets.add(NODE_BROADCAST);
            index++;
        }
        else if (targetArg.equals("each")) {
            targets.add(2);
            targets.add(3);
            targets.add(4);
            targets.add(5);
            index++;
        }
        else if (targetArg.equals("sensor") || targetArg.equals("node")) {
            if (index + 1 >= args.length) {
                usage();
            }

            targets.add(Integer.parseInt(args[index + 1]));
            index += 2;
        }
        else if (targetArg.equals("sensors") || targetArg.equals("nodes")) {
            if (index + 1 >= args.length) {
                usage();
            }

            String[] parts = args[index + 1].split(",");
            for (int i = 0; i < parts.length; i++) {
                targets.add(Integer.parseInt(parts[i].trim()));
            }

            index += 2;
        }
        else {
            try {
                targets.add(Integer.parseInt(targetArg));
                index++;
            } catch (NumberFormatException e) {
                targets.add(NODE_BROADCAST);
            }
        }

        indexRef[0] = index;
        return targets;
    }

    public void sendCommand(int target, short cmd, int value)
            throws IOException {

        SimpleWSNMsg msg = new SimpleWSNMsg();

        msg.set_msg_type(TYPE_CMD);
        msg.set_cmd(cmd);
        msg.set_sender(0);
        msg.set_target(target);
        msg.set_seq(seq++);
        msg.set_value(value);
        msg.set_status((short)0);
        msg.set_mote_time(0);

        msg.set_temperature(0);
        msg.set_humidity(0);
        msg.set_battery(0);

        msg.set_led((short)0);
        msg.set_channel((short)0);
        msg.set_tx_power((short)0);

        moteIF.send(BASE_STATION_ID, msg);

        System.out.printf("[SEND] target=%s cmd=%s value=%d%n",
                target == NODE_BROADCAST ? "all" : "" + target,
                cmdName(cmd),
                value);
    }

    public void messageReceived(int to, Message message) {
        SimpleWSNMsg msg = (SimpleWSNMsg) message;

        int type = msg.get_msg_type();
        int sender = msg.get_sender();
        int cmd = msg.get_cmd();

        if (type == TYPE_DATA) {
            System.out.printf(
                    "[DATA] node=%d seq=%d temp=%d hum=%d voltage=%d " +
                            "led=%d ch=%d txp=%d time=%d%n",
                    sender,
                    msg.get_seq(),
                    msg.get_temperature(),
                    msg.get_humidity(),
                    msg.get_battery(),
                    msg.get_led(),
                    msg.get_channel(),
                    msg.get_tx_power(),
                    msg.get_mote_time()
            );
        }
        else if (type == TYPE_RESP) {
            System.out.printf(
                    "[RESP] node=%d cmd=%s status=%d value=%d " +
                            "temp=%d voltage=%d led=%d ch=%d txp=%d%n",
                    sender,
                    cmdName(cmd),
                    msg.get_status(),
                    msg.get_value(),
                    msg.get_temperature(),
                    msg.get_battery(),
                    msg.get_led(),
                    msg.get_channel(),
                    msg.get_tx_power()
            );
        }
    }

    public static void main(String[] args) throws Exception {
        String source = null;
        int index = 0;

        if (args.length >= 2 && args[0].equals("-comm")) {
            source = args[1];
            index = 2;
        }

        if (args.length - index < 1) {
            usage();
        }

        int[] indexRef = new int[] { index };
        List<Integer> targets = parseTargets(args, indexRef);
        index = indexRef[0];

        if (args.length - index < 1) {
            usage();
        }

        short cmd = parseCommand(args[index]);
        index++;

        int value = 0;

        if (cmd == CMD_SET_LED) {
            if (args.length - index < 1) {
                usage();
            }

            value = Integer.parseInt(args[index]);

            if (value < 0 || value > 7) {
                System.err.println("set-led value must be 0~7");
                System.exit(1);
            }
        }

        SimpleWSNCmd client = new SimpleWSNCmd(source);

        Thread.sleep(500);

        for (int i = 0; i < targets.size(); i++) {
            client.sendCommand(targets.get(i), cmd, value);
            Thread.sleep(300);
        }

        while (true) {
            Thread.sleep(1000);
        }
    }
}