# AccountInbox機制更新

## 背景
2025/3/23時發生DataCenter服務頻寬用盡，導致系統呼叫timeout。  
經盤點後確認AccountInfo服務消耗大量DI存取的頻寬。  
因應此事件與公司ELK將於未來下架，因此盤點AccountInfo的使用與呼叫，並設計優化流程。  

## 當前系統狀況
定型化站內通知信(InboxType > 0)  
如有參數，將參數存msg欄位，標題以I18N資源檔Key值形式存於Title欄位  
內文與標題的內容都紀錄於I18N資源檔中(message.en.property)  
*註冊通知有直接寫入標題內文的情境，須盤點  
  
InboxType < 0 (目前僅有-1)  
目前主要分兩塊發送：後台推送、直接呼叫寫入，InboxType都會寫入-1  
後台推送會先生成一筆Message資料表欄位，並在新增AccountInbox資料時將Message.Id寫入Inbox.MessageId欄位  
API直接呼叫不會有Inbox.MessageId，目前僅有Luckyspin呼叫  

經盤點，目前玩家有兩個情境會增加Inbox消耗資源  

1.  點擊畫面右上角的信箱  
  此時會呼叫此API    
  https://{{WebsiteDomainName}}/api/bt/v1/user/getInboxFromDC  
  而此API中將執行以下操作  
    1.  直接從DI撈取資料   
    2.  從ELK撈取InboxId對應的MessageData  
    其中不包含快取機制，因此每次點擊都會造成DI與ELK的資源消耗。    

2.  登入時將檢查過去一個月是否有未收到的系統MESSAGE，並即時將內容推上ELK  

## 當前資料流與結構

### 事件觸發
``` mermaid
graph LR
  Trigger[系統觸發送Inbox<br>ex: 儲值成功] --> SetType[根據觸發情境設置InboxType] --> InsertInbox[新增Inbox<br>見後述];
```
### 後台新增Message
``` mermaid
graph TB
  NewMessage[後台新增Message<br>發送類別為Member] 
  --> SetType[設置InboxType為-1] 
  --> SetTitle[將Inbox.Title設置為Message標題]
  --> Loop[逐筆處理發送對象] 
  --> ReceiverOnline{收件者在線}
  --是--> InsertInbox[新增Inbox<br>見後述] 
  --> ReceiverLeft{還有收件者}
  --否-->End[結束];
  
  ReceiverOnline --否--> Skip[跳過] --> ReceiverLeft;
  ReceiverLeft--是-->Loop;
```

### API呼叫
``` mermaid
graph TB
  ApiCall[API呼叫<br>目前僅有LuckySpin] 
  --> SetType[設置InboxType為-1] 
  --> SetTitle[根據Request設置Title與MSG]
  --> Loop[逐筆處理發送對象] 
  --> InsertInbox[新增Inbox<br>見後述] 
  --> ReceiverLeft{還有收件者}
  --否-->End[結束];
  ReceiverLeft--是-->Loop;
```

### 登入時補送
``` mermaid
graph TB
  Login[登入] 
  --> ReadMessage[檢查過去30天是否有Message]  
  --> Loop[逐筆處理Message] 
  --> HasInbox{是否已在InboxList}
  --否--> SetInboxFromMessage[設置InboxType=-1<br>根據Message設置Inbox.Title, <br>Inbox.Message, Inbox.MessageID] 
  --> InsertInbox[新增Inbox<br>見後述] 
  --> MessageLeft{還有Message}
  --否-->End[結束];
  MessageLeft--是-->Loop;
  
```

### 新增Inbox
``` mermaid
graph TB
  NewInbox[新增Inbox] --> CheckType{InboxType>0};
  CheckType -->|是<br>代表樣板化通知信| HasParameter{是否傳入參數};
  HasParameter -->|是| WriteMSG[Inbox.Message寫入Json化的參數];
  HasParameter -->|否| MSGNull[Inbox.Message為null];
  MSGNull --> Template[根據InboxType找出Template定義檔, 將標題Key值寫入Inbox.Title];
  WriteMSG --> Template;
  Template --> End;
  
  End--> ELK_Active{是否開啟ELK?};
  ELK_Active --> |是|WriteELK[寫入ELK];

  CheckType --> |否<br>代表客製化訊息| FromMessage{是否來自後台推送};
  FromMessage --> |是| WriteMessageId[將對應的Message.Id寫入Inbox.MessageId欄位];
  FromMessage --> |否| ELK_Active2{是否開啟ELK?};
  WriteMessageId --> ELK_Active2;
  ELK_Active2 --> |是| MSGNull2[將Inbox.Message欄位設為Null<br>寫入ELK的保留原樣];
  ELK_Active2--> |否| End[寫入一筆AccountInbox];
  MSGNull2--> End;
```

### 讀取Inbox
``` mermaid
graph TB
  ReadInbox[讀取Inbox] 
  --> ReadFromDC[從DC取Inbox資料]
  --> CheckType{InboxType>0}
  -->|是<br>代表樣板化通知信| ReadTemplate[根據用戶Language與InboxType從多語系資源檔中取得標題與內文]
  --> HasNSG{Inbox.Message有值?} 
  --> |否| End[顯示資料]; 

  HasNSG 
  --> |是| FillParameter[將Inbox.Message內容轉為字串填入內文]
  --> End;  

  CheckType 
  -->|否<br>代表客製化通知信| EnableELK{是否啟用ELK?}
  --> |否| End;  
  
  EnableELK 
  --> |是| ReadContentFromELK[從ELK取得Inbox.Message]
  --> End;  
```

### 取Inbox未讀
``` mermaid
graph TB
  Entry[取未讀];
  CheckCache{Cache有資料};
  End[顯示資料];  
  QueryDB[從DB撈取未讀數];
  QueryELK[從ELK撈取未讀數];
  WriteCache[寫入Cache<br>10秒];
  UseElk{啟用ELK};

  Entry --> CheckCache;
  CheckCache --是--> End;
  CheckCache --否--> UseElk;
  UseElk --是--> QueryELK;
  UseElk --否--> QueryDB;
  QueryDB --> WriteCache;
  QueryELK --> WriteCache;
  WriteCache --> End;  
```

### DB Table:ACCOUNTINBOX
|UserId|InboxType|Title|Message|MessageId|
|-|-|-|-|-|
A|2|msg.account_inbox.deposit.title|["$200.00"]|-1
B|2|msg.account_inbox.deposit.title|["₹150.56"]|-1
A|-1|Special Promotion!||1234
B|-1|Special Promotion!||1234

### ELK Index:cps-account-inbox
|UserId|InboxType|Title|Message|
|-|-|-|-|
A|2|msg.account_inbox.deposit.title|["$200.00"]|
B|2|msg.account_inbox.deposit.title|["₹150.56"]|
A|-1|Special Promotion!|🎮 Ready to Level Up? Join Our Epic Gaming Event! 🕹️ Gamers, assemble! It's time to dive into an unforgettable adventure during our exclusive online gaming event! From thrilling challenges to amazing rewards, there's something for everyone: 💥 Event Dates: [Insert dates here] 💎 Grand Prizes: Rare skins, in-game currency, and exclusive gear! 🔥 Special Missions: Unlock secrets, defeat bosses, and claim your glory. Gather your squad, sharpen your skills, and get ready for action! Sign up now to secure your spot in the ultimate gaming howdown. Don’t miss out—your chance to win starts [insert start time]!| 
B|-1|Special Promotion!|🎮 Ready to Level Up? Join Our Epic Gaming Event! 🕹️ Gamers, assemble! It's time to dive into an unforgettable adventure during our exclusive online gaming event! From thrilling challenges to amazing rewards, there's something for everyone: 💥 Event Dates: [Insert dates here] 💎 Grand Prizes: Rare skins, in-game currency, and exclusive gear! 🔥 Special Missions: Unlock secrets, defeat bosses, and claim your glory. Gather your squad, sharpen your skills, and get ready for action! Sign up now to secure your spot in the ultimate gaming showdown. Don’t miss out—your chance to win starts [insert start time]!|

## 當前效能問題
1.  透過後台推送大量Inbox時，推送的收件者每人都會在ELK上保留一份相同的內文。  
2.  讀取信件時，會同時到DC和ELK讀取，並且一次讀取全文出來。
3.  查詢未讀數時，只留10秒快取，幾乎等同於客戶每次點擊選單畫面都會進行DB操作。  

## 改善方向
1. 調整AccountInbox資料結構  
  將AccountInbox的Content與主表拆開，避免單一Content重複儲存於每筆Inbox中。  
2. 改善資料讀取流程
  將UnreadCount, Preview等在點開信件前就會看到的資料單獨抽出。  
  點開信件才取Content。 
3. 建立適當的快取機制以避免造成資源消耗  
  調整UnreadCount的快取機制，不再頻繁從DB或ELK撈取資料。  

## 新流程變更概要
1.  新增Inbox Content表與對應的Kafka Topic。  
    - Inbox Content儲存Title, Preview, MessageId, Countent等資料，不儲存收件者資料。  
2.  客制化訊息一律先建立Content。  
    - Inbox內只紀錄Content Id以匹配資料，避免同一訊息佔用多筆資料。  
3.  取得信件未讀、取得信件清單的取資料流程改善。
    - 未讀數儲存於Redis，並直接在事件觸發時調整Redis參數。  
      僅在Reids無值時從DI取得未讀數存入Redis。
    - 取清單時直接從DI取Inbox List, 再根據Content Id找Preview資料。點開信件時才取完整Inbox Content。  

## 新流程

### 事件觸發
觸發後要根據UserId加算Redis未讀數。  
調整於觸發新增Inbox的事件中, 避免呼叫端要檢查。  

### 後台新增Message
``` mermaid
graph TB
  NewMsg[後台新增Message<br>發送類別為Member] 
  --> SetType[設置InboxType為-2] 
  --> NewSummary[根據Message設置Inbox Content] 
  --> SetTitle[將Inbox.Title設置為Content.Id]
  --> Loop[逐筆處理發送對象] 
  --> Login{收件者在線} 
  --是--> InsertInbox[寫入Inbox] 
  --> ReceiverLeft{還有收件者}
  --否--> End[結束];
  
  Login --否-->ReceiverLeft;

  ReceiverLeft--是-->Loop;
  
  style SetType fill:#997700;
  style SetTitle fill:#997700;
  style NewSummary fill:#997700;
  style SetTitle fill:#997700;
```

### API呼叫
``` mermaid
graph TB
  ApiCall[API呼叫<br>目前僅有LuckySpin] 
  --> SetType[設置InboxType為-2] 
  --> NewSummary[根據Request設置Inbox Content]
  --> SetTitle[將Inbox.Title設置為Content.Id]
  --> Loop[逐筆處理發送對象]
  --> InesertInbox[新增Inbox<br>見後述] 
  --> ReceiverLeft{還有收件者}
  --否--> End[結束];
  
  ReceiverLeft--是-->Loop;

  style SetType fill:#997700;
  style SetTitle fill:#997700;
  style NewSummary fill:#997700;
```

### 登入時補送
``` mermaid
graph TB
  Login[登入] 
  --> CheckMessage[取得過去30天的Messages]  
  --是--> Loop[逐筆處理Message] 
  --> HasInbox{是否已在<br>InboxList}
  --否--> HasSummary{是否已有<br>Inbox Content} 
  --否--> SetSummary[設置InboxType=-2<br>根據Message建立Inbox Content] 
  --> SetTitle[將Content.Id寫入inbox.Title]
  --> InsertInbox[新增Inbox<br>見後述] 
  --> MessageLeft{還有<br>Message}
  --否--> End[結束];  
  
  HasSummary --是--> InsertFromSummary[根據Content新增Inbox] --> InsertInbox;
  
  HasInbox --是-->MessageLeft;
  MessageLeft--是-->Loop;
  
  style SetSummary fill:#997700;
  style SetTitle fill:#997700;
  style HasSummary fill:#997700;
  style InsertFromSummary fill:#997700;
```

### 新增Inbox
``` mermaid
graph TB
  NewInbox[新增Inbox] --> CheckTpe{InboxType>0}
  -->|是<br>代表樣板化通知信| CheckParameter{是否傳入參數}
  -->|是| WriteMSG[MSG欄位寫入Json化的參數]
  --> Template[根據InboxType找出Template定義檔, 將標題Key值寫入Title欄位]
  --> End[寫入一筆AccountInbox];

  CheckParameter -->|否| MSGNull[MSG欄位null]
  --> Template;

  CheckTpe 
  --> |否<br>代表客製化訊息| FromMessage{是否來自後台推送}
  --> |是| WriteMessageId[將對應的Message.Id寫入MessageId欄位]
  --> WriteKafka[將訊息內容寫至Kafka的Inbox Content]
  --> PrepareSummary[將建立好的Content.Id寫入Inbox.Title]
  --> End;

  FromMessage --> |否| WriteKafka;
  
  style PrepareSummary fill:#997700;
  style WriteKafka fill:#997700;
```
  
### 讀取Inbox
``` mermaid
graph TB
  ReadInbox[讀取Inbox] 
  --> GetFromDC[從DC取Inbox資料]
  --> isNewFlow{inboxType=-2}
  --否--> CurrentFlow[原有流程<br>詳見前方文件] 
  --> UpdateUnread --> ShowData[顯示資料];

  isNewFlow --是-->  GetFromKafka[從DI取Inbox Content];
  GetFromKafka --> UpdateUnread;

  UpdateUnread[更新Inbox未讀資訊<br>更新Redis計數];

  style isNewFlow fill:#997700;
  style GetFromKafka fill:#997700;
  style UpdateUnread fill:#997700;
```

### 取Inbox未讀
``` mermaid
graph TB
  Entry[取未讀];
  CheckRedis[以UserId查詢確認Redis有無未讀資料];
  End[顯示資料];  
  QueryDB[從DB撈取未讀數];
  WriteRedis[寫入Redis];

  Entry --> CheckRedis;
  CheckRedis --是--> End;
  CheckRedis --否--> QueryDB;
  QueryDB --> WriteRedis;
  WriteRedis --> End;

  style CheckRedis fill:#997700;
  style QueryDB fill:#997700;
  style WriteRedis fill:#997700;
```

## 新流程資料結構

新流程中, DB與Index的資料結構一致

### DB Table: ACCOUNTINBOX
|UserId|InboxType|Title|Message|MessageId
|-|-|-|-|-|
A|2|msg.account_inbox.deposit.title|["$200.00"]|-1
B|2|msg.account_inbox.deposit.title|["₹150.56"]|-1
A|-2|fee38b64-2dd0-4771-8c53-6cd81cb1bd38||1234
B|-2|fee38b64-2dd0-4771-8c53-6cd81cb1bd38||1234

### Kafka Topic:cps-account-inbox-customize-content
|Id|Title|Preview|MessageId|Content|
|-|-|-|-|-|
|fee38b64-2dd0-4771-8c53-6cd81cb1bd38|Special Promotion!|🎮 Ready to Level Up? Join Our Epic Gaming Event! 🕹️|1234|🎮 Ready to Level Up? Join Our Epic Gaming Event! 🕹️ Gamers, assemble! It's time to dive into an unforgettable adventure during our exclusive online gaming event! From thrilling challenges to amazing rewards, there's something for everyone: 💥 Event Dates: [Insert dates here] 💎 Grand Prizes: Rare skins, in-game currency, and exclusive gear! 🔥 Special Missions: Unlock secrets, defeat bosses, and claim your glory. Gather your squad, sharpen your skills, and get ready for action! Sign up now to secure your spot in the ultimate gaming showdown. Don’t miss out—your chance to win starts [insert start time]!|

## 提供API
### 取List
[規格連結](/BackendApibt/v2/user/getInboxList)  
替代當前使用的 /api/bt/v1/user/getInboxFromDC  
傳入傳出規格大致不變，只有Message變更為50字Preview  

並新增ContentId欄位, 在inboxType為-2時會回傳contentId  
直接從DB取得List, 從DI取得Content。  

### 讀Inbox
[規格連結](/BackendApibt/v2/user/readInboxContent)  
傳入inboxId取得完整inbox內容，並更新read。  
直接從DB取得Inbox, 從DI取得Content。

## 需求API
### DI取Inbox Content
傳入參數：Content Id , Content Id List , MessageId, 起訖日  
回傳：以GraphQL形式回傳指定欄位, 通常為Summary或Content.  



## 後續規劃
以下文件***與此次需求無關***，為盤點內容時，整理出的後續可優化方向。

1.  參數化客制Inbox
2.  相關服務&API
3.  排程處理機制

### 1. 參數化客制Inbox
目前的客制訊息，並不會處理變數，儘管是針對大量受眾的促銷，也只是發同樣的文字。  
同時，如果要針對個人發送有內容差異的文字，就得建立多筆 Content。  
這對維運與操作並不是良好的設計，因此應該要規劃新的參數化Inbox方式。

參數化客制Inbox，將把參數依照{0}, {1}等樣板Inbox的格式寫入內文，並同樣除存於AccountInbox的MSG欄位。
傳送參數化客制Inbox的資料規格範例如下：

#### DB Table: ACCOUNTINBOX & ELK Index:cps-account-inbox
|UserId|InboxType|Title|Message|MessageId
|-|-|-|-|-|
A|-2|7d61c7d0-9597-4e8d-b4c4-23bd67ef6683|["Jacob","$200.00"]|1234
B|-2|7d61c7d0-9597-4e8d-b4c4-23bd67ef6683|["Ben","₹150.56"]|1234

#### Kafka Topic:cps-account-inbox-customize-content
|Id|Title|Preview|MessageId|Content
|-|-|-|-|-|
|7d61c7d0-9597-4e8d-b4c4-23bd67ef6683|You've Earned a Special Reward|Dear {0},Thank you for your recent purchase! We are|-1|Dear {0},Thank you for your recent purchase! We are thrilled to inform you that your spending has reached {1}, qualifying you for an exclusive reward.We truly appreciate your support and look forward to providing you with even more great experiences. Please stay tuned for details on how to claim your reward.If you have any questions, feel free to reach out. Enjoy your well-earned reward!|

### 2. 相關服務&API
有了參數化客制API的機制後，我們可以再提供更完善的服務、更簡便地建立參數化的客制訊息。

- 建立客製化Inbox相關API  
  提供建立Inbox Content資料的API，供後續推送使用。也包含配套的CRUD。

- 後台匯入參數化名單  
  後台Message功能，將提供參數化名單的匯入機制。先選擇已事先建立好的Summry，再匯入包含UserId與所需參數的名單。
  因為按照身份群組選擇名單將難以取得參數，因此參數化客制名單應只能透過名單匯入的方式發送。

- 批次推送API  
比照LuckySpin相關程式建立批次推送的API，但須傳入事先建立好的Inbox Content.Id，以及含參數的名單列表。

### 3. 排程處理機制
在後台的Message功能，針對Inbox加入開始時間。並寫排程在指定時間處理Inbox的發送。  
此項規劃可以讓營運方在事前建立推送訊息並於指定時間發送，也可以避免後台使用者於系統繁忙時段推送大量促銷訊息。


## 上線後
### 資料量變化


