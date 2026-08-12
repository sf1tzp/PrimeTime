package fake

import (
	"context"

	"momenttally.com/server/auth"
	"momenttally.com/server/model"
)

// User create a context with a fake user.
func User(id int) context.Context {
	return UserWithPerm(id, true)
}

// UserWithPerm create a context with a fake user.
func UserWithPerm(id int, admin bool) context.Context {
	return auth.WithUser(context.Background(), &model.User{
		ID:    id,
		Name:  "fake",
		Admin: admin,
	})
}
