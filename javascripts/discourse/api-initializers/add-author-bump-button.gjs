import { apiInitializer } from "discourse/lib/api";
import AuthorTopicBumpButton from "../components/author-topic-bump-button";

export default apiInitializer("1.34.0", (api) => {
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { firstButtonKey } }) => {
      dag.add("author-topic-bump", AuthorTopicBumpButton, {
        before: firstButtonKey,
      });
    }
  );
});
