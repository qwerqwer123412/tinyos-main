import javax.swing.*;
import java.awt.*;
import java.awt.event.*;

/**
 * A GridBagLayout based panel with convenience methods for 
 * making various swing items. These methods also ensure a
 * consistent appearance.
 *
 * @author David Gay
 */
public class BagPanel extends JPanel {
    Font boldFont = new Font("Dialog", Font.BOLD, 12);
    Font normalFont = new Font("Dialog", Font.PLAIN, 12);

    GridBagLayout bag;
    GridBagConstraints c;

    /* Create a panel with a bag layout. Create some constraints that
       users can modify prior to creating widgets - the current constraints
       will be applied to all widgets created with makeXXX */
    public BagPanel() {
        bag = new GridBagLayout();
        setLayout(bag);
        c = new GridBagConstraints();
        // Default constraints settings (can be modified as needed)
        c.fill = GridBagConstraints.HORIZONTAL;
        c.insets = new Insets(5, 5, 5, 5); // Padding around components
    }

    /* The makeXXX methods create XXX widgets, apply the current constraints
       to them, and add them to this panel. The widget is returned in case
       the creator needs to keep a reference. */

    public JButton makeButton(String label, ActionListener action) {
        JButton button = new JButton(label);
        button.setFont(boldFont);
        button.addActionListener(action);
        GridBagConstraints tempC = (GridBagConstraints) c.clone(); // Clone the constraints
        bag.setConstraints(button, tempC);
        add(button);
        return button;
    }

    public JCheckBox makeCheckBox(String label, boolean selected) {
        JCheckBox box = new JCheckBox(label, selected);
        box.setFont(normalFont);
        GridBagConstraints tempC = (GridBagConstraints) c.clone(); // Clone the constraints
        bag.setConstraints(box, tempC);
        add(box);
        return box;
    }

    public JLabel makeLabel(String txt, int alignment) {
        JLabel label = new JLabel(txt, alignment);
        label.setFont(boldFont);
        GridBagConstraints tempC = (GridBagConstraints) c.clone(); // Clone the constraints
        bag.setConstraints(label, tempC);
        add(label);
        return label;
    }

    public JTextField makeTextField(int columns, ActionListener action) {
        JTextField tf = new JTextField(columns);
        tf.setFont(normalFont);
        tf.setMaximumSize(tf.getPreferredSize());
        tf.addActionListener(action);
        GridBagConstraints tempC = (GridBagConstraints) c.clone(); // Clone the constraints
        bag.setConstraints(tf, tempC);
        add(tf);
        return tf;
    }

    public JSeparator makeSeparator(int axis) {
        JSeparator sep = new JSeparator(axis);
        GridBagConstraints tempC = (GridBagConstraints) c.clone(); // Clone the constraints
        bag.setConstraints(sep, tempC);
        add(sep);
        return sep;
    }
}
