#[

just some comfort for lists

]#

import lists
export lists

import msgpack4nim

proc isEmpty*[T](list: SinglyLinkedList[T]): bool =
  result = list.head == nil

proc len*[T](list: SinglyLinkedList[T]): int =
  var head = list.head
  while head != nil:
    result.inc
    head = head.next

proc first*[T: ref](list: SinglyLinkedList[T]): T =
  if list.head != nil:
    result = list.head.value

proc removeNext*(head: var SinglyLinkedNode) =
  ## remove the next node in a list
  if head != nil:
    if head.next != nil:
      if head.next.next != nil:
        head.next = head.next.next
      else:
        head.next = nil

proc pack_type*[ByteStream, T](s: ByteStream; x: ref SinglyLinkedNodeObj[T]) =
  {.error: "this can't be right...".}
  s.pack(x.value)
  s.pack(x.next)

proc unpack_type*[ByteStream, T](s: ByteStream; x: var ref SinglyLinkedNodeObj[T]) =
  {.error: "this can't be right...".}
  s.unpack_type(x.value)
  s.unpack_type(x.next)

proc pack_type*[ByteStream, T](s: ByteStream; x: SinglyLinkedList[T]) =
  s.pack(x.head)
  s.pack(x.tail)

proc unpack_type*[ByteStream, T](s: ByteStream; x: var SinglyLinkedList[T]) =
  s.unpack_type(x.head)
  s.unpack_type(x.tail)
