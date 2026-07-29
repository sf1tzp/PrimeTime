package timespan

import (
	"context"

	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

// CreateTimeSpan creates a time span
func (r *ResolverForTimeSpan) CreateTimeSpan(ctx context.Context, start model.Time, end *model.Time, tags []*gqlmodel.InputLabel, note string) (*gqlmodel.TimeSpan, error) {
	timeSpan, err := timespanToInternal(auth.GetUser(ctx).ID, start, end, tags, note)
	if err != nil {
		return nil, err
	}

	if err := tagsExist(r.DB, auth.GetUser(ctx).ID, timeSpan.Tags); err != nil {
		return nil, err
	}

	r.DB.Create(&timeSpan)

	external := timeSpanToExternal(timeSpan)
	return external, nil
}
