import Component from "@glimmer/component";
import { registerDestructor } from "@ember/destroyable";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { settings, themePrefix } from "virtual:theme";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

function responseStatus(error) {
  const status =
    error?.status ||
    error?.jqXHR?.status ||
    error?.responseJSON?.status ||
    error?.response?.status;

  return Number(status);
}

function shouldTryAlternativeEndpoint(error) {
  const status = responseStatus(error);

  return status === 400 || status === 403 || status === 404 || status === 405;
}

function oneMinuteFromNowISO() {
  return new Date(Date.now() + 60 * 1000).toISOString();
}

function parseGroupIntervals(raw) {
  const map = new Map();

  if (!raw) {
    return map;
  }

  raw
    .split("|")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .forEach((entry) => {
      const [groupKey, hoursRaw] = entry.split(":").map((part) => part?.trim());
      const hours = Number(hoursRaw);

      if (!groupKey || Number.isNaN(hours) || hours < 0) {
        return;
      }

      map.set(groupKey.toLowerCase(), hours);
    });

  return map;
}


function parseStructuredGroupIntervals(raw) {
  const rows = Array.isArray(raw)
    ? raw
    : (() => {
        if (!raw || typeof raw !== "string") {
          return [];
        }

        try {
          const parsed = JSON.parse(raw);
          return Array.isArray(parsed) ? parsed : [];
        } catch (_error) {
          return [];
        }
      })();

  return rows
    .map((row) => {
      const groups = Array.isArray(row?.groups)
        ? row.groups.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0)
        : [];
      const intervalHours = Number(row?.interval_hours);

      if (!groups.length || Number.isNaN(intervalHours) || intervalHours < 0) {
        return null;
      }

      return { groups, intervalHours };
    })
    .filter(Boolean);
}
function toNamespacedKey(key) {
  return themePrefix(`author_topic_bump_button.${key}`);
}

function localStorageKey(topicId) {
  return `author-topic-bump:last-bump-ms:${topicId}`;
}

export default class AuthorTopicBumpButton extends Component {
  @service dialog;

  @tracked isLoading = false;
  @tracked nowMs = Date.now();
  @tracked localLastBumpMs = null;

  #tickHandle;

  constructor() {
    super(...arguments);

    this.localLastBumpMs = this.readLocalLastBumpMs();

    this.#tickHandle = setInterval(() => {
      this.nowMs = Date.now();
    }, 1000);

    registerDestructor(this, () => {
      clearInterval(this.#tickHandle);
    });
  }

  static shouldRender({ post, state }) {
    if (!state.currentUser || !post || post.post_number !== 1) {
      return false;
    }

    if (!state.currentUser.canManageTopic) {
      return false;
    }

    const isAuthor = post.username === state.currentUser.username;
    return isAuthor && !post.topic?.closed;
  }

  get topicId() {
    return this.args.post?.topic_id || this.args.post?.topic?.id;
  }

  get currentUser() {
    return this.args.state?.currentUser;
  }

  get titleKey() {
    return toNamespacedKey("title");
  }

  get successKey() {
    return toNamespacedKey("success_scheduled");
  }

  get successModalKey() {
    return toNamespacedKey("success_modal");
  }

  get cooldownTitleKey() {
    return toNamespacedKey("cooldown_title");
  }

  get cooldownLabel() {
    return i18n(toNamespacedKey("cooldown_label"), {
      time: this.formattedRemaining,
    });
  }

  get groupIntervalMap() {
    return parseGroupIntervals(settings.group_bump_intervals);
  }

  get structuredGroupIntervals() {
    return parseStructuredGroupIntervals(settings.group_bump_intervals_structured);
  }

  get intervalHours() {
    const defaultHours = Math.max(0, Number(settings.bump_interval_hours_default || 0));
    const user = this.currentUser;

    if (!user) {
      return defaultHours;
    }

    const groups = Array.isArray(user.groups) ? user.groups : [];
    const userGroupIds = new Set(
      groups
        .map((group) => Number(group?.id))
        .filter((groupId) => Number.isInteger(groupId) && groupId > 0)
    );

    // preferred UI-driven rules (groups selected from forum group picker)
    for (const rule of this.structuredGroupIntervals) {
      if (rule.groups.some((id) => userGroupIds.has(id))) {
        return rule.intervalHours;
      }
    }

    // backward-compatible legacy map
    const map = this.groupIntervalMap;

    // role-based intervals must override trust-level intervals
    if (user.admin && map.has("admins")) {
      return map.get("admins");
    }

    if ((user.moderator || user.staff) && map.has("moderators")) {
      return map.get("moderators");
    }

    const trustLevel = Number(user.trust_level);
    if (Number.isFinite(trustLevel)) {
      const tlKey = `trust_level_${trustLevel}`;
      if (map.has(tlKey)) {
        return map.get(tlKey);
      }
    }

    for (const group of groups) {
      const candidates = [group?.id, group?.name, group?.full_name, group?.slug]
        .filter(Boolean)
        .map((value) => String(value).toLowerCase());

      for (const candidate of candidates) {
        if (map.has(candidate)) {
          return map.get(candidate);
        }
      }
    }

    return defaultHours;
  }

  get intervalMs() {
    return this.intervalHours * 60 * 60 * 1000;
  }

  get topicBumpedMs() {
    const bumpedAt = this.args.post?.topic?.bumped_at || this.args.post?.topic?.last_posted_at;

    if (!bumpedAt) {
      return null;
    }

    const ms = new Date(bumpedAt).getTime();
    return Number.isFinite(ms) ? ms : null;
  }

  get effectiveLastBumpMs() {
    if (this.topicBumpedMs && this.localLastBumpMs) {
      return Math.max(this.topicBumpedMs, this.localLastBumpMs);
    }

    return this.topicBumpedMs || this.localLastBumpMs;
  }

  get remainingMs() {
    if (!this.intervalMs || !this.effectiveLastBumpMs) {
      return 0;
    }

    const nextAllowedMs = this.effectiveLastBumpMs + this.intervalMs;
    return Math.max(0, nextAllowedMs - this.nowMs);
  }

  get isCooldownActive() {
    return this.remainingMs > 0;
  }

  get formattedRemaining() {
    const totalSeconds = Math.ceil(this.remainingMs / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
    }

    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }

  readLocalLastBumpMs() {
    if (!this.topicId) {
      return null;
    }

    const value = localStorage.getItem(localStorageKey(this.topicId));
    if (!value) {
      return null;
    }

    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  writeLocalLastBumpMs(valueMs) {
    if (!this.topicId) {
      return;
    }

    localStorage.setItem(localStorageKey(this.topicId), String(valueMs));
    this.localLastBumpMs = valueMs;
  }

  async requestBump(topicId) {
    try {
      await ajax(`/t/${topicId}/timer`, {
        type: "POST",
        data: {
          status_type: "bump",
          time: oneMinuteFromNowISO(),
        },
      });
      return;
    } catch (error) {
      if (!shouldTryAlternativeEndpoint(error)) {
        throw error;
      }
    }

    try {
      await ajax(`/t/${topicId}/bump`, { type: "PUT" });
      return;
    } catch (error) {
      if (!shouldTryAlternativeEndpoint(error)) {
        throw error;
      }
    }

    await ajax(`/t/${topicId}/reset-bump-date`, { type: "PUT" });
  }

  @action
  async bumpTopic() {
    if (!this.topicId || this.isLoading || this.isCooldownActive) {
      return;
    }

    this.isLoading = true;

    try {
      await this.requestBump(this.topicId);
      this.writeLocalLastBumpMs(Date.now());
      this.args.showFeedback?.(this.successKey);

      if (settings.show_success_modal) {
        this.dialog.alert(i18n(this.successModalKey));
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  <template>
    {{#if this.isCooldownActive}}
      <DButton
        class="post-action-menu__author-topic-bump author-topic-bump-button is-cooldown"
        ...attributes
        @disabled={{true}}
        @icon="far-clock"
        @translatedLabel={{this.cooldownLabel}}
        @title={{this.cooldownTitleKey}}
      />
    {{else}}
      <DButton
        class="post-action-menu__author-topic-bump author-topic-bump-button"
        ...attributes
        @action={{this.bumpTopic}}
        @disabled={{this.isLoading}}
        @icon={{if this.isLoading "spinner" "arrow-up"}}
        @title={{this.titleKey}}
      />
    {{/if}}
  </template>
}
