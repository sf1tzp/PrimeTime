package user

import (
	"context"

	"github.com/jinzhu/copier"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
)

// Users returns all users.
func (r *ResolverForUser) Users(ctx context.Context) ([]*gqlmodel.User, error) {
	var users []model.User
	find := r.DB.Find(&users)
	var result []*gqlmodel.User
	copier.Copy(&result, &users)
	return result, find.Error
}
