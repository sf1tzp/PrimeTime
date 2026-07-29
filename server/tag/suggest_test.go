package tag

import (
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
	"primetime.tools/server/test"
	"primetime.tools/server/test/fake"
)

func TestGQL_SuggestTag_matchesTags(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(1)
	db.User(2)
	resolver := ResolverForTag{DB: db.DB}
	db.Create(&model.TagDefinition{Key: "project", Color: "#fff", UserID: 1})
	db.Create(&model.TagDefinition{Key: "project2", Color: "#fff", UserID: 2})
	db.Create(&model.TagDefinition{Key: "priority", Color: "#fff", UserID: 1})
	db.Create(&model.TagDefinition{Key: "wood", Color: "#fff", UserID: 1})

	tags, err := resolver.SuggestLabelKey(fake.User(1), "pr")

	require.Nil(t, err)
	expected := []*gqlmodel.LabelDefinition{
		{Key: "project", Color: "#fff"},
		{Key: "priority", Color: "#fff"},
	}
	require.Equal(t, expected, tags)
}

func TestGQL_SuggestTag_noMatchingTags(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	db.User(1)
	resolver := ResolverForTag{DB: db.DB}
	db.Create(&model.TagDefinition{Key: "project", Color: "#fff", UserID: 1})
	db.Create(&model.TagDefinition{Key: "wood", Color: "#fff", UserID: 1})

	tags, err := resolver.SuggestLabelKey(fake.User(1), "fire")

	require.Nil(t, err)
	expected := []*gqlmodel.LabelDefinition{}
	require.Equal(t, expected, tags)
}
