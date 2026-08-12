package user

import (
	"context"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
)

// CurrentUser returns the current user.
func (r *ResolverForUser) CurrentUser(ctx context.Context) (*gqlmodel.User, error) {
	user := auth.GetUser(ctx)
	if user == nil {
		return nil, nil
	}
	var result gqlmodel.User
	copier.Copy(&result, user)
	return &result, nil
}
