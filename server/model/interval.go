package model

import (
	"database/sql/driver"
	"fmt"
)

// Interval the interval in which statistics data should be grouped.
// (Relocated from the removed dashboard model; used by the time package.)
type Interval string

// Value for db
func (t Interval) Value() (driver.Value, error) {
	return string(t), nil
}

// Scan for db
func (t *Interval) Scan(value interface{}) error {
	s, ok := value.([]byte)
	if !ok {
		return fmt.Errorf("expected string but was %#v", value)
	}
	*t = Interval(s)
	return nil
}

// No lint errors please.
const (
	IntervalHourly  Interval = "hourly"
	IntervalDaily   Interval = "daily"
	IntervalWeekly  Interval = "weekly"
	IntervalMonthly Interval = "monthly"
	IntervalYearly  Interval = "yearly"
	IntervalSingle  Interval = "single"
)
