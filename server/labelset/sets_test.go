// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Steven Fitzpatrick

package labelset

import (
	"testing"

	"github.com/stretchr/testify/require"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
	"momenttally.com/server/test"
	"momenttally.com/server/test/fake"
)

func labels(pairs ...string) []*gqlmodel.InputLabel {
	result := []*gqlmodel.InputLabel{}
	for i := 0; i+1 < len(pairs); i += 2 {
		result = append(result, &gqlmodel.InputLabel{Key: pairs[i], Value: pairs[i+1]})
	}
	return result
}

func TestGQL_CreateLabelSet_succeeds(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Deep Work", "brain.head.profile", labels("type", "programming", "focus", "deep"), nil, nil)

	require.Nil(t, err)
	require.Equal(t, &gqlmodel.LabelSet{
		ID:         set.ID,
		Name:       "Deep Work",
		SymbolName: "brain.head.profile",
		Labels: []*gqlmodel.Label{
			{Key: "type", Value: "programming"},
			{Key: "focus", Value: "deep"},
		},
		QuickLabels: []*gqlmodel.Label{},
	}, set)
}

func TestGQL_CreateLabelSet_fails_emptyName(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	_, err := resolver.CreateLabelSet(fake.User(5), "  ", "tag", labels(), nil, nil)

	require.EqualError(t, err, "label set name must not be empty")
}

func TestGQL_LabelSets_ordered_andScopedToUser(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(4)
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	_, err := resolver.CreateLabelSet(fake.User(5), "First", "1.circle", labels("a", "1"), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(5), "Second", "2.circle", labels(), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(4), "Other", "tag", labels(), nil, nil)
	require.Nil(t, err)

	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Len(t, sets, 2)
	require.Equal(t, "First", sets[0].Name)
	require.Equal(t, "Second", sets[1].Name)
}

func TestGQL_UpdateLabelSet_replacesMembers(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Meeting", "person.2", labels("type", "meeting"), nil, nil)
	require.Nil(t, err)

	updated, err := resolver.UpdateLabelSet(fake.User(5), set.ID, "Standup", "person.3", labels("type", "meeting", "kind", "standup"), nil, nil)
	require.Nil(t, err)
	require.Equal(t, &gqlmodel.LabelSet{
		ID:         set.ID,
		Name:       "Standup",
		SymbolName: "person.3",
		Labels: []*gqlmodel.Label{
			{Key: "type", Value: "meeting"},
			{Key: "kind", Value: "standup"},
		},
		QuickLabels: []*gqlmodel.Label{},
	}, updated)

	count := new(int)
	db.Model(new(model.LabelSetMember)).Count(count)
	require.Equal(t, 2, *count)
}

func TestGQL_UpdateLabelSet_fails_otherUsersSet(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(4)
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(4), "Other", "tag", labels(), nil, nil)
	require.Nil(t, err)

	_, err = resolver.UpdateLabelSet(fake.User(5), set.ID, "Stolen", "tag", labels(), nil, nil)
	require.Error(t, err)
}

func TestGQL_MoveLabelSet_reorders(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	a, _ := resolver.CreateLabelSet(fake.User(5), "A", "tag", labels(), nil, nil)
	_, err := resolver.CreateLabelSet(fake.User(5), "B", "tag", labels(), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(5), "C", "tag", labels(), nil, nil)
	require.Nil(t, err)

	sets, err := resolver.MoveLabelSet(fake.User(5), a.ID, 2)
	require.Nil(t, err)
	require.Equal(t, "B", sets[0].Name)
	require.Equal(t, "C", sets[1].Name)
	require.Equal(t, "A", sets[2].Name)

	// position clamps to the valid range
	sets, err = resolver.MoveLabelSet(fake.User(5), a.ID, -3)
	require.Nil(t, err)
	require.Equal(t, "A", sets[0].Name)
}

func TestGQL_RemoveLabelSet_deletesMembers(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Meeting", "person.2", labels("type", "meeting"), nil, nil)
	require.Nil(t, err)

	removed, err := resolver.RemoveLabelSet(fake.User(5), set.ID)
	require.Nil(t, err)
	require.Equal(t, "Meeting", removed.Name)

	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Len(t, sets, 0)

	count := new(int)
	db.Model(new(model.LabelSetMember)).Count(count)
	require.Equal(t, 0, *count)
}

func TestGQL_RemoveLabelSet_fails_unknownID(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	_, err := resolver.RemoveLabelSet(fake.User(5), 42)
	require.EqualError(t, err, "label set with id 42 does not exist")
}

func TestGQL_CreateLabelSet_atPosition(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	_, err := resolver.CreateLabelSet(fake.User(5), "A", "tag", labels(), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(5), "B", "tag", labels(), nil, nil)
	require.Nil(t, err)

	position := 0
	created, err := resolver.CreateLabelSet(fake.User(5), "First", "tag", labels(), nil, &position)
	require.Nil(t, err)
	require.Equal(t, "First", created.Name)

	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, "First", sets[0].Name)
	require.Equal(t, "A", sets[1].Name)
	require.Equal(t, "B", sets[2].Name)
}

func TestGQL_UpdateLabelSet_withPosition(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	a, err := resolver.CreateLabelSet(fake.User(5), "A", "tag", labels(), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(5), "B", "tag", labels(), nil, nil)
	require.Nil(t, err)
	_, err = resolver.CreateLabelSet(fake.User(5), "C", "tag", labels(), nil, nil)
	require.Nil(t, err)

	// Rename and move in one call; an over-large position clamps.
	position := 99
	_, err = resolver.UpdateLabelSet(fake.User(5), a.ID, "A2", "tag", labels(), nil, &position)
	require.Nil(t, err)

	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, "B", sets[0].Name)
	require.Equal(t, "C", sets[1].Name)
	require.Equal(t, "A2", sets[2].Name)

	// nil position keeps the current slot.
	_, err = resolver.UpdateLabelSet(fake.User(5), a.ID, "A3", "tag", labels(), nil, nil)
	require.Nil(t, err)
	sets, err = resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, "A3", sets[2].Name)
}

func TestGQL_CreateLabelSet_withQuickLabels(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Deep Work", "brain",
		labels("project", "moment-tally"), labels("type", "review", "type", "debugging"), nil)
	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.Label{{Key: "project", Value: "moment-tally"}}, set.Labels)
	require.Equal(t, []*gqlmodel.Label{
		{Key: "type", Value: "review"},
		{Key: "type", Value: "debugging"},
	}, set.QuickLabels)

	sets, err := resolver.LabelSets(fake.User(5))
	require.Nil(t, err)
	require.Equal(t, set.QuickLabels, sets[0].QuickLabels)
	require.Equal(t, set.Labels, sets[0].Labels)
}

func TestGQL_UpdateLabelSet_nilQuickLabels_preservesThem(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Deep Work", "brain",
		labels("project", "moment-tally"), labels("type", "review"), nil)
	require.Nil(t, err)

	// An older client updates without the quickLabels argument: regular
	// members are replaced, quick labels survive.
	updated, err := resolver.UpdateLabelSet(fake.User(5), set.ID, "Deep Work",
		"brain", labels("project", "server"), nil, nil)
	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.Label{{Key: "project", Value: "server"}}, updated.Labels)
	require.Equal(t, []*gqlmodel.Label{{Key: "type", Value: "review"}}, updated.QuickLabels)
}

func TestGQL_UpdateLabelSet_quickLabels_replaceAndClear(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Deep Work", "brain",
		labels("project", "moment-tally"), labels("type", "review"), nil)
	require.Nil(t, err)

	updated, err := resolver.UpdateLabelSet(fake.User(5), set.ID, "Deep Work",
		"brain", labels("project", "moment-tally"), labels("type", "debugging"), nil)
	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.Label{{Key: "type", Value: "debugging"}}, updated.QuickLabels)

	// An explicit empty list clears them.
	cleared, err := resolver.UpdateLabelSet(fake.User(5), set.ID, "Deep Work",
		"brain", labels("project", "moment-tally"), labels(), nil)
	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.Label{}, cleared.QuickLabels)

	count := new(int)
	db.Model(new(model.LabelSetMember)).Where("quick = ?", true).Count(count)
	require.Equal(t, 0, *count)
}

func TestGQL_RemoveLabelSet_deletesQuickMembers(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(5)

	resolver := ResolverForLabelSet{DB: db.DB}
	set, err := resolver.CreateLabelSet(fake.User(5), "Deep Work", "brain",
		labels("project", "moment-tally"), labels("type", "review"), nil)
	require.Nil(t, err)

	removed, err := resolver.RemoveLabelSet(fake.User(5), set.ID)
	require.Nil(t, err)
	require.Equal(t, []*gqlmodel.Label{{Key: "type", Value: "review"}}, removed.QuickLabels)

	count := new(int)
	db.Model(new(model.LabelSetMember)).Count(count)
	require.Equal(t, 0, *count)
}
