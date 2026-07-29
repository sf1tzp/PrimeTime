// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package user

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/model"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGQL_CreateUser_seedsDefaultLabelSets(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.Create(&model.LabelSet{
		Name:              "Deep Work",
		SymbolName:        "brain.head.profile",
		DefaultCollection: true,
		Members: []model.LabelSetMember{
			{Position: 0, Key: "type", StringValue: "programming"},
		},
	})

	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	created, err := resolver.CreateUser(fake.User(1), "newbie", "secret", false)
	require.Nil(t, err)

	var sets []model.LabelSet
	db.Preload("Members").Where("user_id = ?", created.ID).Find(&sets)
	require.Len(t, sets, 1)
	require.Equal(t, "Deep Work", sets[0].Name)
	require.False(t, sets[0].DefaultCollection)
	require.Len(t, sets[0].Members, 1)

	definition := model.TagDefinition{}
	require.False(t, db.Where("user_id = ? AND key = ?", created.ID, "type").
		Find(&definition).RecordNotFound())
}
