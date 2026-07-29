package user

import (
	"context"

	"github.com/jinzhu/copier"
	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
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
