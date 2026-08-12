package tag

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jinzhu/copier"
	"momenttally.com/server/auth"
	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
)

// syncNow is the clock for sync timestamps (UpdatedAtUTC): whole seconds so
// values round-trip through RFC3339 exactly. Overridable in tests.
var syncNow = func() time.Time { return time.Now().UTC().Truncate(time.Second) }

// CreateTag creates a tag.
func (r *ResolverForTag) CreateLabelDefinition(ctx context.Context, key string, color string) (*gqlmodel.LabelDefinition, error) {
	if strings.TrimSpace(key) == "" {
		return nil, fmt.Errorf("tag must not be empty")
	}
	if strings.Contains(key, " ") {
		return nil, fmt.Errorf("tag must not contain spaces")
	}

	userID := auth.GetUser(ctx).ID
	definition := &model.TagDefinition{
		Key:          strings.ToLower(key),
		Color:        color,
		UserID:       userID,
		UpdatedAtUTC: syncNow(),
	}

	if !r.DB.Where("user_id = ?", userID).Where("key = ?", strings.ToLower(key)).Find(new(model.TagDefinition)).RecordNotFound() {
		return nil, fmt.Errorf("tag with key '%s' does already exist", definition.Key)
	}

	create := r.DB.Create(&definition)
	gqlTag := &gqlmodel.LabelDefinition{}
	copier.Copy(gqlTag, definition)
	gqlTag.ValueColors = []*gqlmodel.LabelValueColor{}
	gqlTag.UpdatedAt = model.Time(definition.UpdatedAtUTC)
	return gqlTag, create.Error
}
