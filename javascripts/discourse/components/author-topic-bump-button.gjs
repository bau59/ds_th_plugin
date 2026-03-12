import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { themePrefix } from "virtual:theme";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function responseStatus(error) {
  return (
    error?.status ||
    error?.jqXHR?.status ||
    error?.responseJSON?.status ||
    error?.response?.status
  );
}

export default class AuthorTopicBumpButton extends Component {
  @tracked isLoading = false;

  static shouldRender({ post, state }) {
    if (!state.currentUser || !post || post.post_number !== 1) {
      return false;
    }

    const isAuthor = post.username === state.currentUser.username;
    return isAuthor && !post.topic?.closed;
  }

  get topicId() {
    return this.args.post?.topic_id || this.args.post?.topic?.id;
  }

  get titleKey() {
    return themePrefix("author_topic_bump_button.title");
  }

  async requestBump(topicId) {
    try {
      await ajax(`/t/${topicId}/bump`, { type: "PUT" });
      return;
    } catch (error) {
      if (responseStatus(error) !== 404) {
        throw error;
      }
    }

    await ajax(`/t/${topicId}/reset-bump-date`, { type: "PUT" });
  }

  @action
  async bumpTopic() {
    if (!this.topicId || this.isLoading) {
      return;
    }

    this.isLoading = true;

    try {
      await this.requestBump(this.topicId);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  <template>
    <DButton
      class="post-action-menu__author-topic-bump author-topic-bump-button"
      ...attributes
      @action={{this.bumpTopic}}
      @disabled={{this.isLoading}}
      @icon={{if this.isLoading "spinner" "arrow-up"}}
      @title={{this.titleKey}}
    />
  </template>
}
