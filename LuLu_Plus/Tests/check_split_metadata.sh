#!/bin/sh
#
# check_split_metadata.sh - compare the methods a binary implements before and after a split
#
# why this exists: the suites in this folder test the decision logic through their own copies of
# it, and the windows are wired up in nibs whose connections are matched by selector name at run
# time, so nothing here would notice a method that stayed behind in the old file, or one that
# moved into two files. Both are visible in the built binary: every Objective-C method compiles
# to a symbol named -[Class selector] or +[Class selector], so the two lists can be compared.
#
# usage: check_split_metadata.sh <binary before> <binary after>
#

set -o pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <binary before> <binary after>"
    exit 2
fi

before=$1
after=$2

if [ ! -f "$before" ] || [ ! -f "$after" ]; then
    echo "ERROR: one of the binaries isn't there: $before / $after"
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

#both binaries are universal and the symbol table is per architecture, so take one slice from each
arch=x86_64
lipo -archs "$before" | grep -q arm64 && arch=arm64

for pair in "$before:old" "$after:new"; do
    binary=${pair%%:*}
    label=${pair##*:}

    if lipo -archs "$binary" | grep -q " "; then
        lipo -thin "$arch" "$binary" -output "$work/$label" || exit 1
    else
        cp "$binary" "$work/$label"
    fi

    #every method the binary implements; duplicates kept, so a method compiled twice is seen
    #note: a category's methods compile to -[Class(Category) selector], and splitting a class over
    #       files is meant to change exactly that decoration and nothing else, so it's folded away;
    #       the compiler's `.cold.N' branches come and go with where the code sits, so likewise
    nm "$work/$label" | sed -n 's/^.* [-+] *\[\([^]]*\)\]\(.*\)$/\1 \2/p' |
        sed 's/([^)]*)//; s/\.cold\.[0-9]*$//' | sort > "$work/$label.methods"

    #the ivars each class has: a category never adds storage, and the outlets a nib reconnects to
    #       are ivars, so this is the other thing a split must leave exactly as it was
    nm "$work/$label" | sed -n 's/^.* _OBJC_IVAR_\$_\(.*\)$/\1/p' | sort > "$work/$label.ivars"
done

echo "methods implemented before: $(wc -l < "$work/old.methods" | tr -d ' ')"
echo "methods implemented after:  $(wc -l < "$work/new.methods" | tr -d ' ')"

#note: an extra `.cold.N' branch can appear or disappear when code moves between files, since it
#       is where the compiler parks a path it expects rarely; those are folded away above, and the
#       two lists below are the only thing that matters
lost=$(comm -23 "$work/old.methods" "$work/new.methods" | grep -c . || true)
gained=$(comm -13 "$work/old.methods" "$work/new.methods" | grep -c . || true)
ivars=$(comm -3 "$work/old.ivars" "$work/new.ivars" | grep -c . || true)

echo "methods gone:               $lost"
echo "methods new:                $gained"
echo "ivars changed:              $ivars"

[ "$lost" != "0" ] && { echo "--- gone ---"; comm -23 "$work/old.methods" "$work/new.methods"; }
[ "$gained" != "0" ] && { echo "--- new ---"; comm -13 "$work/old.methods" "$work/new.methods"; }
[ "$ivars" != "0" ] && { echo "--- ivars ---"; comm -3 "$work/old.ivars" "$work/new.ivars"; }

if [ "$lost" = "0" ] && [ "$gained" = "0" ] && [ "$ivars" = "0" ]; then
    echo "RESULT: the class is made of exactly the same methods as before"
    exit 0
fi

echo "RESULT: something moved that shouldn't have - see the lists above"
exit 1
