package weaveapi

import (
	"fmt"
	"net"

	. "github.com/weaveworks/weave/common"
)

func (client *Client) ipamOp(ID string, op string) (*net.IPNet, error) {
	Log.Debugf("IPAM operation %s for %s", op, ID)
	ip, err := httpVerb(op, fmt.Sprintf("%s/ip/%s", client.baseUrl, ID), nil)
	if err != nil {
		return nil, err
	}
	return parseIP(ip)
}

// returns an IP for the ID given, allocating a fresh one if necessary
func (client *Client) AllocateIP(ID string) (*net.IPNet, error) {
	return client.ipamOp(ID, "POST")
}

// returns an IP for the ID given, or nil if one has not been
// allocated
func (client *Client) LookupIP(ID string) (*net.IPNet, error) {
	return client.ipamOp(ID, "GET")
}

// release an IP which is no longer needed
func (client *Client) ReleaseIP(ID string) error {
	_, err := client.ipamOp(ID, "DELETE")
	return err
}

func parseIP(body string) (*net.IPNet, error) {
	ip, ipnet, err := net.ParseCIDR(string(body))
	if err != nil {
		return nil, err
	}
	ipnet.IP = ip
	return ipnet, nil
}
