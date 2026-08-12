package tag

import (
	"context"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
)

// SuggestTag suggests a tag.
func (r *ResolverForTag) SuggestLabelKey(ctx context.Context, query string) ([]*gqlmodel.LabelDefinition, error) {
	var suggestions []model.TagDefinition
	find := r.DB.Where("user_id = ?", auth.GetUser(ctx).ID).Where("Key LIKE ?", query+"%").Find(&suggestions)
	var result []*gqlmodel.LabelDefinition
	copier.Copy(&result, &suggestions)
	return result, find.Error
}
