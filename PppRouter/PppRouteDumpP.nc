#include <iprouting.h>

module PppRouteDumpP {
  uses {
    interface Boot;
    interface UDP;
    interface ForwardingTable;
  }
} implementation {

  event void Boot.booted() {
    call UDP.bind(2000);
  }

  event void UDP.recvfrom(struct sockaddr_in6 *from, void *data,
                          uint16_t len, struct ip6_metadata *meta) {
    struct route_entry *entry;
    struct in6_addr node2;
    char yes[] = "fec0::2 DAO yes\n";
    char no[] = "fec0::2 DAO no\n";

    memset(&node2, 0, sizeof(node2));
    inet_pton6("fec0::2", &node2);

    entry = call ForwardingTable.lookupRoute(node2.s6_addr, 128);
    if (entry != NULL && entry->prefixlen == 128) {
      call UDP.sendto(from, yes, sizeof(yes) - 1);
    } else {
      call UDP.sendto(from, no, sizeof(no) - 1);
    }
  }
}
