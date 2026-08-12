package tag

import (
	"context"
	"fmt"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
)

// RemoveTag removes a tag.
func (r *ResolverForTag) RemoveLabelDefinition(ctx context.Context, key string) (*gqlmodel.LabelDefinition, error) {
	tag := model.TagDefinition{}
	userID := auth.GetUser(ctx).ID
	if r.DB.Where(&model.TagDefinition{UserID: userID, Key: key}).Find(&tag).RecordNotFound() {
		return nil, fmt.Errorf("tag with key '%s' does not exist", key)
	}

	tx := r.DB.Begin()
	if err := tx.Where(model.TagDefinition{Key: key, UserID: userID}).
		Delete(new(model.TagDefinition)).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	timeSpansIdsOfUser := tx.Model(new(model.TimeSpan)).
		Select("id").
		Where(&model.TimeSpan{UserID: userID}).
		SubQuery()

	if err := tx.
		Where("time_span_id in ?", timeSpansIdsOfUser).
		Where(&model.TimeSpanTag{Key: key}).
		Delete(new(model.TimeSpanTag)).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	if err := tx.
		Where("user_id = ? AND key = ?", userID, key).
		Delete(new(model.LabelValueColor)).Error; err != nil {
		tx.Rollback()
		return nil, err
	}

	remove := tx.Commit()
	gqlTag := &gqlmodel.LabelDefinition{}
	copier.Copy(gqlTag, &tag)
	return gqlTag, remove.Error
}
