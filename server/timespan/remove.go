package timespan

import (
	"context"
	"fmt"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// RemoveTimeSpan removes a timespan.
func (r *ResolverForTimeSpan) RemoveTimeSpan(ctx context.Context, id int) (*gqlmodel.TimeSpan, error) {
	timeSpan := model.TimeSpan{ID: id}
	if r.DB.Preload("Tags").Where("user_id = ?", auth.GetUser(ctx).ID).Find(&timeSpan).RecordNotFound() {
		return nil, fmt.Errorf("timespan with id %d does not exist", timeSpan.ID)
	}

	remove := r.DB.Where(&model.TimeSpan{ID: id}).Delete(new(model.TimeSpan))

	external := timeSpanToExternal(timeSpan)
	return external, remove.Error
}
