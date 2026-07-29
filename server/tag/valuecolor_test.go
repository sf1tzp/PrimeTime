// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package tag

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGQL_SetLabelValueColor_succeeds_createsOverride(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})

	resolver := ResolverForTag{DB: db.DB}
	definition, err := resolver.SetLabelValueColor(fake.User(5), "type", "meeting", "#f00")

	require.Nil(t, err)
	require.Equal(t, &gqlmodel.LabelDefinition{
		Key:   "type",
		Color: "#fff",
		ValueColors: []*gqlmodel.LabelValueColor{
			{Value: "meeting", Color: "#f00"},
		},
	}, definition)
}

func TestGQL_SetLabelValueColor_succeeds_replacesOverride(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "meeting", Color: "#f00"})

	resolver := ResolverForTag{DB: db.DB}
	definition, err := resolver.SetLabelValueColor(fake.User(5), "type", "meeting", "#0f0")

	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.LabelValueColor{
		{Value: "meeting", Color: "#0f0"},
	}, definition.ValueColors)

	count := new(int)
	db.Model(new(model.LabelValueColor)).Count(count)
	require.Equal(t, 1, *count)
}

func TestGQL_SetLabelValueColor_fails_unknownKey(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForTag{DB: db.DB}
	_, err := resolver.SetLabelValueColor(fake.User(5), "nope", "meeting", "#f00")

	require.EqualError(t, err, "label definition with key 'nope' does not exist")
}

func TestGQL_SetLabelValueColor_scopedToUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(4)
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 4})
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})
	db.Create(&model.LabelValueColor{UserID: 4, Key: "type", Value: "meeting", Color: "#aaa"})

	resolver := ResolverForTag{DB: db.DB}
	definition, err := resolver.SetLabelValueColor(fake.User(5), "type", "meeting", "#f00")

	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.LabelValueColor{
		{Value: "meeting", Color: "#f00"},
	}, definition.ValueColors)

	other := model.LabelValueColor{}
	db.Where("user_id = ?", 4).Find(&other)
	require.Equal(t, "#aaa", other.Color)
}

func TestGQL_ClearLabelValueColor_succeeds(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "meeting", Color: "#f00"})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "email", Color: "#00f"})

	resolver := ResolverForTag{DB: db.DB}
	definition, err := resolver.ClearLabelValueColor(fake.User(5), "type", "meeting")

	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.LabelValueColor{
		{Value: "email", Color: "#00f"},
	}, definition.ValueColors)
}

func TestGQL_ClearLabelValueColor_fails_unknownKey(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForTag{DB: db.DB}
	_, err := resolver.ClearLabelValueColor(fake.User(5), "nope", "meeting")

	require.EqualError(t, err, "label definition with key 'nope' does not exist")
}

func TestGQL_LabelDefinitions_includeValueColors(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	user := db.User(5)
	user.NewTagDefinition("type")
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "meeting", Color: "#f00"})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "email", Color: "#00f"})

	resolver := ResolverForTag{DB: db.DB}
	definitions, err := resolver.LabelDefinitions(fake.User(5))

	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.LabelDefinition{
		{Key: "type", ValueColors: []*gqlmodel.LabelValueColor{
			{Value: "email", Color: "#00f"},
			{Value: "meeting", Color: "#f00"},
		}},
	}, definitions)
}

func TestGQL_UpdateLabelDefinition_renameMovesValueColors(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "meeting", Color: "#f00"})

	resolver := ResolverForTag{DB: db.DB}
	newKey := "kind"
	definition, err := resolver.UpdateLabelDefinition(fake.User(5), "type", &newKey, "#fff")

	require.Nil(t, err)
	require.Equal(t, "kind", definition.Key)
	require.Equal(t, []*gqlmodel.LabelValueColor{
		{Value: "meeting", Color: "#f00"},
	}, definition.ValueColors)

	moved := model.LabelValueColor{}
	require.False(t, db.Where("user_id = ? AND key = ?", 5, "kind").Find(&moved).RecordNotFound())
}

func TestGQL_RemoveLabelDefinition_deletesValueColors(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)
	db.Create(&model.TagDefinition{Key: "type", Color: "#fff", UserID: 5})
	db.Create(&model.LabelValueColor{UserID: 5, Key: "type", Value: "meeting", Color: "#f00"})

	resolver := ResolverForTag{DB: db.DB}
	_, err := resolver.RemoveLabelDefinition(fake.User(5), "type")

	require.Nil(t, err)
	count := new(int)
	db.Model(new(model.LabelValueColor)).Count(count)
	require.Equal(t, 0, *count)
}
