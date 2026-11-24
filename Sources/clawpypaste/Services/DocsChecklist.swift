import Foundation

// Google Docs turns pasted <li role="checkbox" aria-checked=…> items into
// real, clickable checklist items. The checkbox images are the ones Docs
// itself puts on the clipboard, so apps that don't understand the role
// (Pages, Word, Notes) still show a checkbox instead of a bare line.
enum DocsChecklist {
    static func item(_ innerHTML: String, checked: Bool) -> String {
        let img = checked ? checkedPNG : uncheckedPNG
        let alt = checked ? "checked" : "unchecked"
        // Strike-through goes on the text only — on the <li> it also struck
        // through the list indent, leaving a stray line in Docs.
        let text = checked ? "<span style=\"text-decoration: line-through;\">\(innerHTML)</span>" : innerHTML
        return "<li role=\"checkbox\" aria-checked=\"\(checked)\" style=\"list-style-type: none;\">"
            + "<img src=\"\(img)\" width=\"17.6\" height=\"17.6\" alt=\"\(alt)\" style=\"margin-right: 3px;\">"
            + text + "</li>"
    }

    private static let uncheckedPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAAA1ElEQVR4Ae3bMQ4BURSFYY2xBuwQ7BIkTGxFRj9Oo9RdkXn5TvL3L19u+2ZmZmZmZhVbpH26pFcaJ9IrndMudb/CWadHGiden1bll9MIzqd79SUd0thY20qga4NA50qgoUGgoRJo/NL/V/N+QIAAAQIECBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQIEyFeEZyXQpUGgUyXQrkGgTSVQl/qGcG5pnkq3Sn0jOMv0k3Vpm05pmNjfsGPalFyOmZmZmdkbSS9cKbtzhxMAAAAASUVORK5CYII="
    private static let checkedPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEgAAABICAYAAABV7bNHAAABbElEQVR4Ae3bsU4CYRDEcRsxodZE8Q0BbS258l5MwESJNL6HOfrPKdhyxeBcwk5mkn9F98sGIOSuPM/zPM/zPI+xG/SEtuiAWpEOaIOWaDIWziP6RK14OzSjX44ITvTBvqRn1MRaMIHeBIE2TKBBEGhgArWkKmtJBjKQgQxkIANd/Aw0NVC+O7RHvYFynHasN1COE/UGynGiXgOIjxOtdIH4OGJAfBwxID6OGBAfRwiIjyMARMCpCjRF5+72Dzhd5R+rHfpC92NeTlWgLl5PkQg4RYBynBSJgFMGKMNJkQg4lYFeUDuFRMCpBXQOEgGnDtA/kPg4xT7m2y/tCd9zKgOdviTC5RQEIiAFjh4QASlw9IAISIEjCURAWvmf1UDKcQwUSDmOgWLdMcxA7BnIQAYykIEM5EcRvplAW0GgNRNoKQg0ZwJN0E4I5x1dI+pmgSSA84BG2QQt0LrYG/eAXtGccjme53me53me9wPjPWZWjhktAQAAAABJRU5ErkJggg=="
}
