// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package model

import "time"

// TimeSpanTombstone records a deleted timespan so syncing devices can drop
// their copy too (see the timeSpanChanges query). Written by removeTimeSpan;
// rows are small and kept indefinitely — a user deletes far fewer timespans
// than they create.
type TimeSpanTombstone struct {
	// TimeSpanID is the id the deleted timespan had. Not auto-incremented:
	// it is assigned from the deleted row.
	TimeSpanID int `gorm:"primary_key"`
	UserID     int `gorm:"type:int REFERENCES users(id) ON DELETE CASCADE"`
	// DeletedAtUTC is the server time of the deletion (whole seconds).
	DeletedAtUTC time.Time
}
