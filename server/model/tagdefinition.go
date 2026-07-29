package model

import "time"

// TagDefinition describes a tag.
type TagDefinition struct {
	Key    string
	UserID int `gorm:"type:int REFERENCES users(id) ON DELETE CASCADE"`
	Color  string
	Usages int `gorm:"-"`
	// UpdatedAtUTC is the server time of the last write (whole seconds),
	// for last-writer-wins sync. Managed explicitly, not by gorm.
	UpdatedAtUTC time.Time
}
