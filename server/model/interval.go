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

// Scan for db. sqlite text columns arrive as []byte on older go-sqlite3 and
// as string on newer releases, so accept either.
func (t *Interval) Scan(value interface{}) error {
	switch s := value.(type) {
	case []byte:
		*t = Interval(s)
	case string:
		*t = Interval(s)
	default:
		return fmt.Errorf("expected string or []byte but was %#v", value)
	}
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
