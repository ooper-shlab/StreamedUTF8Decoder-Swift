//
//  StreamedUTF8Decoder.swift
//  OOPUtils
//
//  Created by OOPer in cooperation with shlab.jp, on 2016/12/16.
//  Copyright © 2016 OOPer (NAGATA, Atsuyuki). All rights reserved.
//
/*
 Copyright (c) 2016, OOPer(NAGATA, Atsuyuki)
 All rights reserved.
 
 Use of any parts(functions, classes or any other program language components)
 of this file is permitted with no restrictions, unless you
 redistribute or use this file in its entirety without modification.
 In this case, providing any sort of warranties or not is the user's responsibility.
 
 Redistribution and use in source and/or binary forms, without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

protocol StreamedDecoder {
    ///Add bytes sequence which will be decoded as following the rest of the preceding data.
    mutating func append(_ data: Data) throws
    
    ///Retrieve already decoded String which does not contain already retrived part.
    mutating func retrieveDecodedString() -> String
    
    ///Finalize decoding, if there are any number of undecoded bytes remaining, causes `onInvalidSequence` action.
    mutating func finalize() throws
    
    ///Reset the instance to the initial state.
    mutating func reset()
    
    ///Defines the action performed when an invalid sequence is found, default value is `ignore`.
    var onInvalidSequence: InvalidSequence {get set}
    
    ///Set to true, if any number of invalid sequences are found, after reset.
    var hasErrors: Bool {get}
}

///Defines each case performed on each invalid sequence
enum InvalidSequence {
    ///Igonored, though, `hasError` is set to true.
    case ignore
    ///Throws specified error, without setting `onInvalidSequence` to this case, you can use `try!` safely.
    case `throw`(Error)
    ///Put replacement character (or character sequence) at each apperance of invalid sequence.
    case replace(String)
}

class StreamedUTF8Decoder: StreamedDecoder {
    var onInvalidSequence: InvalidSequence = .ignore
    private(set) var hasErrors: Bool = false
    //UTF-8 specific settings
    var allowsRedundantEncoding: Bool = false
    private let allowsSurrogatesReencoded: Bool = false //String.Encoding.utf8 does not allow reencoded surrogates
    
    private var data: Data = Data()
    private(set) var decodedString: String = ""
    
    private func isFollowingByte(_ byte: UInt8) -> Bool {
        return byte & 0b1100_0000 == 0b1000_0000 //10xx_xxxx
    }
    private func countForFirstByte(_ byte: UInt8) -> Int? {
        if byte & 0b1000_0000 == 0b0000_0000 {return 1} //0xxx_xxxx
        if byte & 0b1110_0000 == 0b1100_0000 {return 2} //110x_xxxx
        if byte & 0b1111_0000 == 0b1110_0000 {return 3} //1110_xxxx
        if byte & 0b1111_1000 == 0b1111_0000 {return 4} //1111_0xxx
        //5 or 6-byte UTF-8 sequence is invalid in the current Unicode spec.
        return nil
    }
    private func putDecodedString(_ startingPosition: Int, _ currentPosition: Int) {
        if startingPosition < currentPosition {
            let subdata = self.data.subdata(in: startingPosition..<currentPosition)
            self.decodedString.append(String(data: subdata, encoding: .utf8)!)
        }
    }
    private func doOnInvalidSequence() throws {
        self.hasErrors = true
        switch onInvalidSequence {
        case .ignore:
            break
        case .throw(let error):
            throw error
        case .replace(let str):
            self.decodedString.append(str)
        }
    }
    ///Find a new position possibly valid as a first byte of character in UTF-8. Returns nil when not found in the current `data`.
    private func getNextValidBytePosition(_ currentPosition: Int) -> Int? {
        for i in currentPosition+1..<self.data.count {
            let byte = self.data[i]
            if !isFollowingByte(byte) {
                return i
            }
        }
        return nil
    }
    //Requirement: firstBytePosition + count <= self.data.count
    //           : byte at firstBytePosition is valid as a first byte of UTF-8 encoded character
    private func isValidSequence(_ firstBytePosition: Int, _ count: Int) -> Bool {
        let minimumCodePoint: [UInt32] = [0x0000_0080, 0x0000_0800, 0x0001_0000]
        var codePoint: UInt32 = 0
        let firstByte = self.data[firstBytePosition]
        switch count {
        case 1:
            return true
        case 2:
            codePoint = UInt32(firstByte & 0b0001_1111)
        case 3:
            codePoint = UInt32(firstByte & 0b0000_1111)
        case 4:
            codePoint = UInt32(firstByte & 0b0000_0111)
        default:
            fatalError("bad count")
        }
        for i in 1..<count {
            let byte = self.data[firstBytePosition+i]
            if !isFollowingByte(byte) {
                return false
            }
            codePoint = (codePoint << 6) | UInt32(byte & 0b0011_1111)
        }
        //Checking bad code points.
        if codePoint > 0x0010_FFFF {return false}
        if codePoint == 0xFFFE || codePoint == 0xFFFF {return false}
        if !allowsSurrogatesReencoded && (0xD800...0xDFFF).contains(codePoint) {return false}
        if !allowsRedundantEncoding && codePoint < minimumCodePoint[count-2] {return false}
        return true
    }
    
    func append(_ data: Data) throws {
        self.data.append(data)
        try decodeString()
    }
    func retrieveDecodedString() -> String {
        let result = self.decodedString
        self.decodedString = ""
        return result
    }
    func finalize() throws {
        if !self.data.isEmpty {
            try doOnInvalidSequence()
            self.data = Data()
        }
    }
    func reset() {
        self.data = Data();
        self.decodedString = ""
        self.hasErrors = false
    }
    
    private func decodeString() throws {
        var position = 0
        var startingPosition = 0
        while position < self.data.count {
            let byte = self.data[position]
            if isFollowingByte(byte) {
                //invalid for first byte
                //findNextValidByte
                if let nextValidBytePosition = getNextValidBytePosition(position) {
                    putDecodedString(startingPosition, position)
                    try doOnInvalidSequence()
                    position = nextValidBytePosition
                    startingPosition = position
                } else {
                    break
                }
            } else if let count = countForFirstByte(byte) {
                if position+count > self.data.count {
                    break
                }
                if isValidSequence(position, count) {
                    position += count
                } else {
                    if let nextValidBytePosition = getNextValidBytePosition(position) {
                        putDecodedString(startingPosition, position)
                        try doOnInvalidSequence()
                        position = nextValidBytePosition
                        startingPosition = position
                    } else {
                        break
                    }
                }
            } else {
                //single invalid byte
                putDecodedString(startingPosition, position)
                try doOnInvalidSequence()
                position += 1
                startingPosition = position
            }
        }
        putDecodedString(startingPosition, position)
        self.data = self.data.subdata(in: position..<self.data.count)
    }
}
