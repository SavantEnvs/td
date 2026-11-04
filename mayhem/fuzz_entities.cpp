// Message-entity finders over arbitrary UTF-8 text. First byte selects the skip flags.
#include "td/telegram/MessageEntity.h"

#include "td/utils/common.h"
#include "td/utils/Slice.h"
#include "td/utils/utf8.h"

#include <cstddef>
#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data, std::size_t size) {
  if (size < 1) {
    return -1;
  }
  auto mode = data[0];
  td::string str(reinterpret_cast<const char *>(data) + 1, size - 1);
  if (!td::check_utf8(str)) {
    return -1;
  }
  td::Slice text(str);

  td::find_entities(text, (mode & 1) != 0, (mode & 2) != 0);
  td::find_mentions(text);
  td::find_bot_commands(text);
  td::find_hashtags(text);
  td::find_cashtags(text);
  td::find_bank_card_numbers(text);
  td::find_ton_addresses(text);
  td::find_tg_urls(text);
  td::find_urls(text);
  td::find_media_timestamps(text);
  td::is_email_address(text);
  return 0;
}
