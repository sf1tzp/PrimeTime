package user

import (
	"context"
	"fmt"

	"github.com/jinzhu/copier"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// RemoveUser removes a user
func (r *ResolverForUser) RemoveUser(ctx context.Context, id int) (*gqlmodel.User, error) {
	user := model.User{ID: id}
	if r.DB.Find(&user).RecordNotFound() {
		return nil, fmt.Errorf("user with id %d does not exist", user.ID)
	}

	remove := r.DB.Delete(&user)
	gqlUser := &gqlmodel.User{}
	copier.Copy(gqlUser, &user)
	return gqlUser, remove.Error
}
