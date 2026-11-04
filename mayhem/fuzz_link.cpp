// LinkManager URL / tg:// / t.me link parsing over arbitrary UTF-8 text. First byte selects flags.
#include "td/telegram/LinkManager.h"
#include "td/telegram/td_api.h"

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
  td::string link_str(reinterpret_cast<const char *>(data) + 1, size - 1);
  if (!td::check_utf8(link_str)) {
    return -1;
  }

  auto internal_link = td::LinkManager::parse_internal_link(link_str, (mode & 1) != 0);
  if (internal_link != nullptr) {
    auto object = internal_link->get_internal_link_type_object();
    if (object != nullptr) {
      auto r_link = td::LinkManager::get_internal_link(object, (mode & 2) != 0);
      if (r_link.is_ok()) {
        td::LinkManager::parse_internal_link(r_link.ok(), (mode & 1) != 0);
      }
    }
  }

  td::LinkManager::is_internal_link(link_str);
  td::LinkManager::check_link(link_str, (mode & 4) != 0, (mode & 8) != 0);
  td::LinkManager::get_checked_link(link_str, (mode & 4) != 0, (mode & 8) != 0);
  td::LinkManager::get_message_link_info(link_str);
  td::LinkManager::get_dialog_boost_link_info(link_str);
  td::LinkManager::get_link_user_id(link_str);
  td::LinkManager::get_link_custom_emoji_id(link_str);
  td::LinkManager::get_link_formatted_date(link_str);
  td::LinkManager::get_dialog_invite_link_hash(link_str);
  td::LinkManager::get_dialog_filter_invite_link_slug(link_str);
  td::LinkManager::get_group_call_invite_link_slug(link_str);
  td::LinkManager::get_instant_view_link_url(link_str);
  td::LinkManager::get_instant_view_link_rhash(link_str);
  td::LinkManager::has_video_chat_invite_hash(link_str);
  return 0;
}
