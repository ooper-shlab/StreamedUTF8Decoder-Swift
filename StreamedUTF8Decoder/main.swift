//
//  main.swift
//  StreamedUTF8Decoder
//
//  Created by 開発 on 2016/12/16.
//  Copyright © 2016 OOPer (NAGATA, Atsuyuki). All rights reserved.
//

import Foundation

//
// A simple example of showing how to use
//

//let str = "éあ💔"
//print(str.utf8.map{String(format:"%02X", $0)})
//["C3", "A9", "E3", "81", "82", "F0", "9F", "92", "94"]
let dataArray: [[UInt8]] = [[0xC3, 0xA9, 0xE3, 0x81], [0x82, 0xF0, 0x9F, 0x92], [0x94]]
let s8Decoder = StreamedUTF8Decoder()
for data in dataArray {
    try! s8Decoder.append(Data(bytes: data))
    let s = s8Decoder.retrieveDecodedString()
    print(s)
}
try! s8Decoder.finalize()
print(s8Decoder.retrieveDecodedString())

s8Decoder.reset()
for data in dataArray {
    try! s8Decoder.append(Data(bytes: data))
}
try! s8Decoder.finalize()
print(s8Decoder.retrieveDecodedString())
