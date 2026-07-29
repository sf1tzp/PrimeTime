// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package preference

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGQL_UserPreferences_defaults(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForPreferences{DB: db.DB}
	preferences, err := resolver.UserPreferences(fake.User(5))

	require.Nil(t, err)
	require.Equal(t, &gqlmodel.UserPreferences{
		ColorByValue:      true,
		MenuLabelSetLimit: 5,
	}, preferences)
}

func TestGQL_SetUserPreferences_roundTrip(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForPreferences{DB: db.DB}
	set, err := resolver.SetUserPreferences(fake.User(5), gqlmodel.InputUserPreferences{
		ColorByValue:      false,
		MenuLabelSetLimit: 0, // 0 = all
	})
	require.Nil(t, err)
	require.Equal(t, &gqlmodel.UserPreferences{
		ColorByValue:      false,
		MenuLabelSetLimit: 0,
	}, set)

	got, err := resolver.UserPreferences(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, set, got)

	// setting again replaces (upsert, not insert)
	set, err = resolver.SetUserPreferences(fake.User(5), gqlmodel.InputUserPreferences{
		ColorByValue:      true,
		MenuLabelSetLimit: 3,
	})
	require.Nil(t, err)
	got, err = resolver.UserPreferences(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, set, got)
	require.Equal(t, 3, got.MenuLabelSetLimit)
}

func TestGQL_UserPreferences_scopedToUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(4)
	db.User(5)

	resolver := ResolverForPreferences{DB: db.DB}
	_, err := resolver.SetUserPreferences(fake.User(4), gqlmodel.InputUserPreferences{
		ColorByValue:      false,
		MenuLabelSetLimit: 1,
	})
	require.Nil(t, err)

	preferences, err := resolver.UserPreferences(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, &gqlmodel.UserPreferences{
		ColorByValue:      true,
		MenuLabelSetLimit: 5,
	}, preferences)
}
