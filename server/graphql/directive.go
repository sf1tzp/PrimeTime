package graphql

import (
	"primetime.tools/server/auth"
	"primetime.tools/server/generated/gqlschema"
)

// NewDirective creates a new directive.
func NewDirective() gqlschema.DirectiveRoot {
	return gqlschema.DirectiveRoot{
		HasRole: auth.HasRole(),
	}
}
