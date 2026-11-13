# frozen_string_literal: true

# Helpers for the English / Simplified Chinese language switcher.
module LocaleHelper
  LOCALE_OPTIONS = [
    { code: "en", label: "English" },
    { code: "zh-CN", label: "简体中文" },
  ].freeze

  # Builds a link to the current page with only the `locale` query parameter
  # changed. Keeping the rest of the query string means switching language
  # doesn't drop tags, page numbers, or search filters.
  def locale_switch_url(locale)
    path, query = request.fullpath.split("?", 2)
    pairs = query.to_s.split("&").reject { |pair| pair.split("=", 2).first == "locale" }
    pairs << "locale=#{locale}"
    "#{path}?#{pairs.join("&")}"
  end

  # Renders "English / 简体中文" with the active language highlighted.
  def locale_switcher_links
    links = LOCALE_OPTIONS.map do |option|
      code = option[:code]
      active = I18n.locale.to_s == code
      link_to option[:label], locale_switch_url(code),
              class: (active ? "current font-bold locale-active" : "locale-inactive"),
              lang: code, hreflang: code, rel: "nofollow",
              title: t("locale_switcher.title"), "aria-current": (active ? "true" : nil)
    end

    safe_join(links, " / ")
  end
end
