package services

import "strings"

// EstimateTokens is a fallback when upstream usage accounting is unavailable.
func EstimateTokens(payload map[string]any) (prompt, completion, total int) {
	acc := strings.Builder{}

	if model, ok := payload["prompt"].(string); ok {
		acc.WriteString(model)
	}
	if messages, ok := payload["messages"].([]any); ok {
		for _, m := range messages {
			if row, ok := m.(map[string]any); ok {
				if c, ok := row["content"].(string); ok {
					acc.WriteString(" ")
					acc.WriteString(c)
				}
			}
		}
	}

	wordCount := len(strings.Fields(acc.String()))
	prompt = int(float64(wordCount) * 1.3)
	if prompt < 1 {
		prompt = 1
	}
	completion = int(float64(prompt) * 0.6)
	if completion < 1 {
		completion = 1
	}
	total = prompt + completion
	return
}
