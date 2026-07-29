package convert

import (
	"primetime.tools/server/generated/gqlmodel"
	"primetime.tools/server/model"
)

func tagFiltersToExternal(tags []model.DashboardTagFilter, include bool) []*gqlmodel.TimeSpanTag {
	if len(tags) == 0 {
		return nil
	}

	result := []*gqlmodel.TimeSpanTag{}
	for _, tag := range tags {
		if tag.Include == include {
			result = append(result, &gqlmodel.TimeSpanTag{
				Key:   tag.Key,
				Value: tag.StringValue,
			})
		}
	}
	return result
}

func TagFiltersToInternal(gqls []*gqlmodel.InputTimeSpanTag, include bool) []model.DashboardTagFilter {
	result := make([]model.DashboardTagFilter, 0)
	for _, tag := range gqls {
		result = append(result, tagFilterToInternal(*tag, include))
	}
	return result
}

func tagFilterToInternal(gqls gqlmodel.InputTimeSpanTag, include bool) model.DashboardTagFilter {
	return model.DashboardTagFilter{
		Key:         gqls.Key,
		StringValue: gqls.Value,
		Include:     include,
	}
}
