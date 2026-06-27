/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@Entry
@Component
struct Index {
  @State message:string = 'Hello ArkUI on macOS'
  build() {
    Column({ space: 20 }) {
      Text(this.message)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.Black)
      Text('方舟 ArkUI · 原生 macOS 渲染')
        .fontSize(22)
        .fontColor(Color.Blue)
      Row()
        .width('70%').height(90)
        .backgroundColor(Color.Blue).borderRadius(16)
      Row()
        .width('55%').height(90)
        .backgroundColor(Color.Orange).borderRadius(16)
      Row()
        .width('40%').height(90)
        .backgroundColor(Color.Green).borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFEFEFF4')
    .justifyContent(FlexAlign.Center)
  }
}