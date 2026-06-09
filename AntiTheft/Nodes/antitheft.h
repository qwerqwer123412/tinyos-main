#ifndef ANTITHEFT_H
#define ANTITHEFT_H

enum {
  ALERT_LEDS = 1 << 0,     // Use bit shift for clarity
  ALERT_SOUND = 1 << 1,
  ALERT_RADIO = 1 << 2,
  ALERT_ROOT = 1 << 3,

  DETECT_DARK = 1 << 0,    // Use bit shift for clarity
  DETECT_ACCEL = 1 << 1,

  DEFAULT_ALERT = ALERT_LEDS,
  DEFAULT_DETECT = DETECT_DARK,
  DEFAULT_CHECK_INTERVAL = 1000
};

// Use enum for message types to avoid magic numbers
typedef enum {
  AM_SETTINGS = 54,
  AM_THEFT = 99,
  AM_ALERT = 22,
  DIS_SETTINGS = 42,
  COL_ALERTS = 11
} message_types_t;

// Struct to hold anti-theft system settings
typedef nx_struct settings {
  nx_uint8_t alert;            // Bitmask for alert types (e.g., ALERT_LEDS | ALERT_SOUND)
  nx_uint8_t detect;           // Bitmask for detection types (e.g., DETECT_DARK | DETECT_ACCEL)
  nx_uint16_t checkInterval;   // Time interval for checking
} settings_t;

// Struct for alert messages
typedef nx_struct alert {
  nx_uint16_t stolenId;        // ID of the stolen item
} alert_t;

// Utility macros for setting and checking bitmask flags
#define SET_ALERT_TYPE(settings, type) ((settings).alert |= (type))
#define CLEAR_ALERT_TYPE(settings, type) ((settings).alert &= ~(type))
#define IS_ALERT_TYPE_SET(settings, type) ((settings).alert & (type))

#define SET_DETECT_TYPE(settings, type) ((settings).detect |= (type))
#define CLEAR_DETECT_TYPE(settings, type) ((settings).detect &= ~(type))
#define IS_DETECT_TYPE_SET(settings, type) ((settings).detect & (type))

#endif
