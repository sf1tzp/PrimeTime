// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package model

// UserPreferences is the per-user client state a second device should
// inherit. Colouring *data* (key and value colours) already syncs via label
// definitions; these are the remaining bits. Absence of a row means the
// defaults apply (see DefaultUserPreferences).
type UserPreferences struct {
	UserID int `gorm:"primary_key;unique_index"`
	// ColorByValue colours timespans by label value (PrimeTime's default
	// behaviour); key colours remain for navigating Label Review.
	ColorByValue bool
	// MenuLabelSetLimit is how many label sets the menu shows (0 = all).
	MenuLabelSetLimit int
}

// DefaultUserPreferences returns the preferences of a fresh user.
func DefaultUserPreferences(userID int) UserPreferences {
	return UserPreferences{
		UserID:            userID,
		ColorByValue:      true,
		MenuLabelSetLimit: 5,
	}
}
