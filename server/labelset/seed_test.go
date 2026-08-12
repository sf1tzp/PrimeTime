// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package labelset

import (
	"testing"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
	"momenttally.com/server/test/fake"
)

func template(db *test.Database, position int, name string, symbol string, members ...model.LabelSetMember) model.LabelSet {
	set := model.LabelSet{
		Name:              name,
		SymbolName:        symbol,
		Position:          position,
		DefaultCollection: true,
		Members:           members,
	}
	db.Create(&set)
	return set
}

func member(position int, key string, value string) model.LabelSetMember {
	return model.LabelSetMember{Position: position, Key: key, StringValue: value}
}

func TestSeedDefaultLabelSets_copiesCollection(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	template(db, 0, "Deep Work", "brain.head.profile", member(0, "type", "programming"))
	template(db, 1, "Meeting", "person.2", member(0, "type", "meeting"), member(1, "kind", ""))

	require.Nil(t, SeedDefaultLabelSets(db.DB, 5))

	resolver := ResolverForLabelSet{DB: db.DB}
	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Len(t, sets, 2)
	require.Equal(t, "Deep Work", sets[0].Name)
	require.Equal(t, "brain.head.profile", sets[0].SymbolName)
	require.Equal(t, "Meeting", sets[1].Name)
	require.Len(t, sets[1].Labels, 2)
	require.Equal(t, "type", sets[1].Labels[0].Key)
	require.Equal(t, "meeting", sets[1].Labels[0].Value)

	// definitions were created for the referenced keys (once per key)
	var definitions []model.TagDefinition
	db.Where("user_id = ?", 5).Order("key").Find(&definitions)
	require.Len(t, definitions, 2)
	require.Equal(t, "kind", definitions[0].Key)
	require.Equal(t, "type", definitions[1].Key)
	require.Equal(t, DefaultLabelColor, definitions[1].Color)
}

func TestSeedDefaultLabelSets_keepsExistingDefinitions(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{UserID: 5, Key: "type", Color: "#abc"})
	template(db, 0, "Deep Work", "tag", member(0, "type", "programming"))

	require.Nil(t, SeedDefaultLabelSets(db.DB, 5))

	definition := model.TagDefinition{}
	require.False(t, db.Where("user_id = ? AND key = ?", 5, "type").Find(&definition).RecordNotFound())
	require.Equal(t, "#abc", definition.Color)
}

func TestSeedDefaultLabelSets_emptyCollection_isNoop(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	// a set owned by a user is not a template, even if flagged
	userID := 5
	db.Create(&model.LabelSet{UserID: &userID, Name: "Mine", DefaultCollection: true})

	require.Nil(t, SeedDefaultLabelSets(db.DB, 5))

	resolver := ResolverForLabelSet{DB: db.DB}
	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Len(t, sets, 1) // just the pre-existing one, no copies
}
