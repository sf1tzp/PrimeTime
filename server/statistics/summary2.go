package statistics

import (
	"context"
	stdtime "time"

	"momenttally.com/server/generated/gqlmodel"
	"momenttally.com/server/model"
	"momenttally.com/server/time"
)

// Stats2 another version of the stats endpoint
func (r *ResolverForStatistics) Stats2(ctx context.Context, now model.Time, stats gqlmodel.InputStatsSelection) ([]*gqlmodel.RangedStatisticsEntries, error) {
	var ranges []*gqlmodel.Range

	// Moment Tally v1 has no per-user week configuration: weeks run
	// Monday through Sunday.
	staticRanges, err := time.ParseRange(now.OmitTimeZone(),
		time.RelativeRange{From: stats.Range.From, To: stats.Range.To},
		time.InternalInterval(stats.Interval),
		stdtime.Monday,
		stdtime.Sunday)
	if err != nil {
		return nil, err
	}
	for _, r := range staticRanges {
		ranges = append(ranges, &gqlmodel.Range{Start: model.Time(r.From), End: model.Time(r.To)})
	}

	return r.Stats(ctx, ranges, stats.Keys, stats.ExcludeLabels, stats.IncludeLabels)
}
