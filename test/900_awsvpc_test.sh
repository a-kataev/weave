#! /bin/bash

. ./config.sh

C1=10.32.0.2
C2=10.40.0.1
UNIVERSE=10.32.0.0/12

function routetableid {
    host=$1
    json=$(mktemp json.XXXXXXXXXX)
    aws ec2 describe-instances                                      \
        --filters "Name=instance-state-name,Values=pending,running" \
                  "Name=tag:weavenet_ci,Values=true"                \
                  "Name=tag:Name,Values=$host" > $json
    vpcid=$(jq -r ".Reservations[0].Instances[0].NetworkInterfaces[0].VpcId" $json)
    aws ec2 describe-route-tables                                   \
        --filters "Name=vpc-id,Values=$vpcid" > $json
    jq -r ".RouteTables[0].RouteTableId" $json
    rm $json
}

function cleanup_routetable {
    id=$1
    json=$(mktemp json.XXXXXXXXXX)
    echo "Cleaning up routes $json"
    aws ec2 describe-route-tables --route-table-ids $id > $json
    cidrs=$(jq -r ".RouteTables[0].Routes[] | select(has(\"NetworkInterfaceId\")) |
                    .DestinationCidrBlock" $json)
    for cidr in $cidrs; do
        echo "Removing $cidr route"
        aws ec2 delete-route                \
            --route-table-id $id            \
            --destination-cidr-block $cidr
    done
    rm $json
}

start_suite "AWSVPC"

VPC_ROUTE_TABLE_ID=$(routetableid $HOST1)
cleanup_routetable $VPC_ROUTE_TABLE_ID

WEAVE_NO_FASTDP=1 weave_on $HOST1 launch            \
        --ipalloc-range $UNIVERSE                   \
        --awsvpc                                    \
        --aws-routetableid=$VPC_ROUTE_TABLE_ID
WEAVE_NO_FASTDP=1 weave_on $HOST2 launch            \
        --ipalloc-range $UNIVERSE                   \
        --awsvpc                                    \
        --aws-routetableid=$VPC_ROUTE_TABLE_ID      \
        $HOST1

run_on $HOST1 "echo '1' | sudo tee --append /proc/sys/net/ipv4/conf/weave/proxy_arp"
run_on $HOST2 "echo '1' | sudo tee --append /proc/sys/net/ipv4/conf/weave/proxy_arp"

weave_on $HOST1 expose
weave_on $HOST2 expose

run_on $HOST1 "sudo ip route delete $UNIVERSE || true"
run_on $HOST2 "sudo ip route delete $UNIVERSE || true"

start_container $HOST1 --name=c1
start_container $HOST2 --name=c2

assert_raises "exec_on $HOST1 c1 $PING $C2"
assert_raises "exec_on $HOST1 c2 $PING $C1"

trap "cleanup_routetable $VPC_ROUTE_TABLE_ID" EXIT

end_suite
