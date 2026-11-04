// Markdown / HTML entity parsers and fix_formatted_text over arbitrary UTF-8 text.
// First byte: low 2 bits pick the parser, the rest are fix_formatted_text flags.
#include "td/telegram/MessageEntity.h"

#include "td/utils/common.h"
#include "td/utils/Slice.h"
#include "td/utils/Status.h"
#include "td/utils/utf8.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data, std::size_t size) {
  if (size < 1) {
    return -1;
  }
  auto mode = data[0];
  td::string text(reinterpret_cast<const char *>(data) + 1, size - 1);
  if (!td::check_utf8(text)) {
    return -1;
  }

  td::Result<td::vector<td::MessageEntity>> r_entities;
  switch (mode & 3) {
    case 0:
      r_entities = td::parse_markdown(text);
      break;
    case 1:
      r_entities = td::parse_markdown_v2(text);
      break;
    default:
      r_entities = td::parse_html(text);
      break;
  }
  if (r_entities.is_error()) {
    return 0;
  }
  auto entities = r_entities.move_as_ok();
  auto status = td::fix_formatted_text(text, entities, (mode & 4) != 0, (mode & 8) != 0, (mode & 16) != 0,
                                       (mode & 32) != 0, (mode & 64) != 0, (mode & 128) != 0);
  (void)status;
  return 0;
}
