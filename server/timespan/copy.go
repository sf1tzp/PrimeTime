package timespan

import (
	"context"
	"fmt"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// CopyTimeSpan copies a time span.
func (r *ResolverForTimeSpan) CopyTimeSpan(ctx context.Context, id int, start model.Time, end *model.Time) (*gqlmodel.TimeSpan, error) {
	old := &model.TimeSpan{ID: id}

	if r.DB.Preload("Tags").Where("user_id = ?", auth.GetUser(ctx).ID).Find(old).RecordNotFound() {
		return nil, fmt.Errorf("time span with id %d does not exist", id)
	}

	return r.CreateTimeSpan(ctx, start, end, tagsToInputTag(old.Tags), old.Note)
}
