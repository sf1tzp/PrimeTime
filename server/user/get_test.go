package user

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/test"
)

func TestGQL_Users(t *testing.T) {
	db := test.InMemoryDB(t)
	defer db.Close()
	resolver := ResolverForUser{DB: db.DB, PassStrength: 4}
	db.NewUserPass(1, "jmattheis", unicornPW, true)
	db.NewUserPass(2, "broderpeters", ponyPW, false)

	users, err := resolver.Users(context.Background())

	require.Nil(t, err)
	expected := []*gqlmodel.User{
		{
			Name:  "jmattheis",
			ID:    1,
			Admin: true,
		},
		{
			Name:  "broderpeters",
			ID:    2,
			Admin: false,
		},
	}
	require.Equal(t, expected, users)
}
