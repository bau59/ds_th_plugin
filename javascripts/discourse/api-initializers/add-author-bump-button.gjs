import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import I18n from "I18n";

function updateButtonState(button, isLoading) {
  button.disabled = isLoading;
  button.classList.toggle("is-loading", isLoading);

  if (isLoading) {
    button.dataset.defaultLabel = button.textContent;
    button.textContent = I18n.t("author_topic_bump_button.loading");
  } else {
    button.textContent = button.dataset.defaultLabel || I18n.t("author_topic_bump_button.bump");
  }
}

async function bumpTopic(button) {
  const topicId = button.dataset.topicId;
  if (!topicId) {
    return;
  }

  updateButtonState(button, true);

  try {
    await ajax(`/t/${topicId}/bump`, { type: "PUT" });
    button.textContent = I18n.t("author_topic_bump_button.bumped");

    setTimeout(() => {
      button.textContent = button.dataset.defaultLabel || I18n.t("author_topic_bump_button.bump");
      button.disabled = false;
      button.classList.remove("is-loading");
    }, 1800);
  } catch (error) {
    updateButtonState(button, false);
    popupAjaxError(error);
  }
}

function attachButtons(currentUsername) {
  document.querySelectorAll("tr.topic-list-item").forEach((row) => {
    if (row.dataset.authorBumpReady === "true") {
      return;
    }

    const topicId = row.dataset.topicId;
    const authorLink = row.querySelector("td.posters a[data-user-card]");
    const actionsCell = row.querySelector("td.posters");

    if (!topicId || !authorLink || !actionsCell) {
      return;
    }

    const authorUsername = authorLink.dataset.userCard;
    if (!authorUsername || authorUsername !== currentUsername) {
      return;
    }

    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-icon-text author-topic-bump-button";
    button.dataset.topicId = topicId;
    button.textContent = I18n.t("author_topic_bump_button.bump");

    button.addEventListener("click", () => bumpTopic(button));

    actionsCell.appendChild(button);
    row.dataset.authorBumpReady = "true";
  });
}

export default apiInitializer("1.14.0", (api) => {
  const currentUser = api.getCurrentUser();

  if (!currentUser?.username) {
    return;
  }

  api.onPageChange(() => {
    attachButtons(currentUser.username);
    requestAnimationFrame(() => attachButtons(currentUser.username));
    setTimeout(() => attachButtons(currentUser.username), 500);
  });
});
