import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

const loadingTopicIds = new Set();

function canShowBumpButton(attrs, currentUsername) {
  if (!currentUsername || !attrs?.firstPost) {
    return false;
  }

  const postAuthor = attrs.username || attrs?.user?.username;
  if (!postAuthor || postAuthor !== currentUsername) {
    return false;
  }

  const topicClosed = attrs.topic_closed || attrs?.topic?.closed;
  return !topicClosed;
}

function extractTopicId(attrs) {
  return attrs?.topic_id || attrs?.topic?.id;
}

export default apiInitializer("1.14.0", (api) => {
  const currentUser = api.getCurrentUser();

  if (!currentUser?.username) {
    return;
  }

  api.addPostMenuButton("author-topic-bump", (attrs) => {
    if (!canShowBumpButton(attrs, currentUser.username)) {
      return null;
    }

    const topicId = extractTopicId(attrs);
    if (!topicId) {
      return null;
    }

    const isLoading = loadingTopicIds.has(topicId);

    return {
      action: "authorTopicBump",
      icon: isLoading ? "spinner" : "arrow-up",
      className: `author-topic-bump-button ${isLoading ? "is-loading" : ""}`,
      title: "author_topic_bump_button.title",
      position: "first",
    };
  });

  api.attachWidgetAction("post", "authorTopicBump", async function () {
    const topicId = extractTopicId(this.attrs);

    if (!topicId || loadingTopicIds.has(topicId)) {
      return;
    }

    loadingTopicIds.add(topicId);
    this.scheduleRerender();

    try {
      await ajax(`/t/${topicId}/bump`, { type: "PUT" });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      loadingTopicIds.delete(topicId);
      this.scheduleRerender();
    }
  });
});
